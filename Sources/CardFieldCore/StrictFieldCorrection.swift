import Foundation

/// Configuration for syntax-validated use of lower-ranked OCR readings.
public struct StrictFieldCorrectionOptions: Equatable, Sendable {
  public enum Mode: String, Codable, Sendable {
    case disabled
    case enabled
  }

  public var mode: Mode

  public init(mode: Mode = .disabled) {
    self.mode = mode
  }
}

enum StrictFieldFamily: String, Sendable {
  case email
  case phone
  case website
}

struct StrictFieldCorrectionResolution: Equatable, Sendable {
  var tokens: [OCRToken]
  var reviewFamilies: Set<StrictFieldFamily>
}

enum StrictFieldCorrectionEngine {
  static let minimumObservationConfidence = 0.55
  static let minimumValidScore = 0.90
  static let minimumScoreMargin = 0.30

  static func resolve(
    tokens: [OCRToken],
    rules: EffectiveRules,
    options: StrictFieldCorrectionOptions
  ) -> StrictFieldCorrectionResolution {
    guard options.mode == .enabled else {
      return StrictFieldCorrectionResolution(
        tokens: tokens,
        reviewFamilies: []
      )
    }

    var resolved: [OCRToken] = []
    var reviewFamilies = Set<StrictFieldFamily>()
    for token in tokens {
      let outcome = resolve(token: token, rules: rules)
      resolved.append(outcome.token)
      if let reviewFamily = outcome.reviewFamily {
        reviewFamilies.insert(reviewFamily)
      }
    }
    return StrictFieldCorrectionResolution(
      tokens: resolved,
      reviewFamilies: reviewFamilies
    )
  }

  private struct TokenOutcome {
    var token: OCRToken
    var reviewFamily: StrictFieldFamily?
  }

  private struct Candidate: Equatable {
    var text: String
    var normalizedValue: String
    var score: Double
    var phoneKind: PhoneKind?
  }

  private static func resolve(token: OCRToken, rules: EffectiveRules) -> TokenOutcome {
    let families = indicatedFamilies(in: token.text, rules: rules)
    guard families.count == 1, let family = families.first, !token.alternatives.isEmpty else {
      return TokenOutcome(token: token, reviewFamily: nil)
    }

    let primary = candidate(text: token.text, family: family, rules: rules)
    let primaryPhoneKind = family == .phone ? phoneLabelKind(in: token.text, rules: rules) : nil
    let alternatives = uniqueCandidates(
      token.alternatives.compactMap { candidate(text: $0, family: family, rules: rules) }
    ).filter { family != .phone || $0.phoneKind == primaryPhoneKind }
    let validAlternatives = alternatives.filter { $0.score >= minimumValidScore }
    let primaryIsValid = (primary?.score ?? 0) >= minimumValidScore

    if primaryIsValid {
      let competing = validAlternatives.contains {
        $0.normalizedValue != primary?.normalizedValue
      }
      return TokenOutcome(
        token: token,
        reviewFamily: competing ? family : nil
      )
    }

    guard !validAlternatives.isEmpty else {
      return TokenOutcome(token: token, reviewFamily: nil)
    }
    guard validAlternatives.count == 1 else {
      return TokenOutcome(token: token, reviewFamily: family)
    }

    let selected = validAlternatives[0]
    let primaryScore = primary?.score ?? 0
    guard selected.score - primaryScore >= minimumScoreMargin else {
      return TokenOutcome(token: token, reviewFamily: family)
    }
    guard token.confidence >= minimumObservationConfidence else {
      return TokenOutcome(token: token, reviewFamily: family)
    }

    var correctedToken = token
    correctedToken.text = normalizedWhitespace(selected.text)
    return TokenOutcome(token: correctedToken, reviewFamily: nil)
  }

  private static func uniqueCandidates(_ candidates: [Candidate]) -> [Candidate] {
    var bestByValue: [String: Candidate] = [:]
    for candidate in candidates.sorted(by: candidateOrder) {
      if let current = bestByValue[candidate.normalizedValue], current.score >= candidate.score {
        continue
      }
      bestByValue[candidate.normalizedValue] = candidate
    }
    return bestByValue.values.sorted(by: candidateOrder)
  }

  private static func candidateOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    if lhs.normalizedValue != rhs.normalizedValue {
      return lhs.normalizedValue < rhs.normalizedValue
    }
    return lhs.text < rhs.text
  }

  private static func candidate(
    text: String,
    family: StrictFieldFamily,
    rules: EffectiveRules
  ) -> Candidate? {
    let normalizedText = normalizedWhitespace(text)
    switch family {
    case .email:
      return emailCandidate(normalizedText)
    case .website:
      return websiteCandidate(normalizedText)
    case .phone:
      return phoneCandidate(normalizedText, rules: rules)
    }
  }

  private static func indicatedFamilies(in text: String, rules: EffectiveRules)
    -> Set<StrictFieldFamily>
  {
    let folded = text.cardFieldFolded
    var families = Set<StrictFieldFamily>()
    if folded.contains("@") {
      families.insert(.email)
    }
    if folded.contains("http://") || folded.contains("https://") || folded.contains("www.") {
      families.insert(.website)
    }
    let digitCount = text.filter(\.isNumber).count
    if digitCount >= 4,
      folded.contains("+") || phoneLabelKind(in: text, rules: rules) != nil
    {
      families.insert(.phone)
    }
    return families
  }

  private static func emailCandidate(_ text: String) -> Candidate? {
    guard
      let match = singleMatch(
        pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z0-9]{2,24}"#,
        in: text,
        options: [.caseInsensitive]
      ),
      allowedRemainder(
        text, removing: match.range, labels: ["e", "email", "e-mail", "mail", "이메일"])
    else { return nil }

    let value = match.value.lowercased()
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    let local = String(parts[0])
    let domain = String(parts[1])
    guard !local.hasPrefix("."), !local.hasSuffix("."), !local.contains(".."),
      validDomainLabels(domain)
    else { return nil }
    return Candidate(
      text: text,
      normalizedValue: value,
      score: domainScore(domain),
      phoneKind: nil
    )
  }

  private static func websiteCandidate(_ text: String) -> Candidate? {
    guard
      let match = singleMatch(
        pattern: #"(?:https?://|www\.)(?:[A-Z0-9\-]+\.)+[A-Z0-9]{2,24}(?:/[^\s]*)?"#,
        in: text,
        options: [.caseInsensitive]
      ),
      allowedRemainder(
        text,
        removing: match.range,
        labels: ["w", "web", "website", "url", "homepage", "홈페이지"]
      )
    else { return nil }

    let normalized = match.value.lowercased().trimmingCharacters(
      in: CharacterSet(charactersIn: ".,")
    )
    guard let host = websiteHost(normalized), validDomainLabels(host) else { return nil }
    return Candidate(
      text: text,
      normalizedValue: normalized,
      score: domainScore(host),
      phoneKind: nil
    )
  }

  private static func phoneCandidate(_ text: String, rules: EffectiveRules) -> Candidate? {
    guard let match = singleMatch(pattern: #"(?:\+?\d[\d ()\-.]{5,}\d)"#, in: text) else {
      return nil
    }
    let remainder = remainderText(text, removing: match.range)
    let kind = remainder.isEmpty ? nil : phoneLabelKind(in: remainder + " 0000000", rules: rules)
    guard remainder.isEmpty || kind != nil else { return nil }
    let digits = match.value.filter(\.isNumber)
    guard (7...15).contains(digits.count) else { return nil }
    let normalized = match.value.filter { $0.isNumber || $0 == "+" }
    return Candidate(text: text, normalizedValue: normalized, score: 1, phoneKind: kind)
  }

  private static func websiteHost(_ value: String) -> String? {
    var host = value
    if let scheme = host.range(of: "://") {
      host = String(host[scheme.upperBound...])
    }
    if let slash = host.firstIndex(of: "/") {
      host = String(host[..<slash])
    }
    if host.hasPrefix("www.") {
      host.removeFirst(4)
    }
    return host.isEmpty ? nil : host
  }

  private static func validDomainLabels(_ domain: String) -> Bool {
    let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2 else { return false }
    return labels.allSatisfy { label in
      !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
        && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
  }

  private static func domainScore(_ domain: String) -> Double {
    guard let suffix = domain.split(separator: ".").last?.lowercased() else { return 0 }
    let suspiciousSuffixes: Set<String> = [
      "c0m", "comm", "con", "corn", "nct", "ner", "0rg", "orrg",
    ]
    guard !suspiciousSuffixes.contains(suffix) else { return 0.45 }
    guard suffix.count >= 2, suffix.count <= 24, suffix.allSatisfy(\.isLetter) else {
      return 0.45
    }
    return 1
  }

  private static func phoneLabelKind(in text: String, rules: EffectiveRules) -> PhoneKind? {
    let folded = text.cardFieldFolded.trimmingCharacters(in: .whitespacesAndNewlines)
    return rules.phoneLabels.sorted { lhs, rhs in
      if lhs.key.count != rhs.key.count { return lhs.key.count > rhs.key.count }
      return lhs.key < rhs.key
    }.first { label, _ in
      guard folded.hasPrefix(label) else { return false }
      guard folded.count > label.count else { return true }
      let boundary = folded.index(folded.startIndex, offsetBy: label.count)
      return !folded[boundary].isLetter && !folded[boundary].isNumber
    }?.value
  }

  private static func allowedRemainder(
    _ text: String,
    removing range: Range<String.Index>,
    labels: Set<String>
  ) -> Bool {
    let remainder = remainderText(text, removing: range).cardFieldFolded
    return remainder.isEmpty || labels.contains(remainder)
  }

  private static func remainderText(
    _ text: String,
    removing range: Range<String.Index>
  ) -> String {
    let remainder = String(text[..<range.lowerBound]) + String(text[range.upperBound...])
    return remainder.trimmingCharacters(
      in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":;|,-"))
    )
  }

  private struct TextMatch {
    var value: String
    var range: Range<String.Index>
  }

  private static func singleMatch(
    pattern: String,
    in text: String,
    options: NSRegularExpression.Options = []
  ) -> TextMatch? {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
      return nil
    }
    let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard matches.count == 1, let range = Range(matches[0].range, in: text) else { return nil }
    return TextMatch(value: String(text[range]), range: range)
  }

  private static func normalizedWhitespace(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
