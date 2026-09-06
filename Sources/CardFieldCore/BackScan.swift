import Foundation

/// Errors emitted while decoding a vCard payload from a business-card barcode.
public enum VCardParsingError: Error, Equatable, Sendable {
  case unsupportedEncoding
  case invalidEnvelope
  case unsupportedVersion
  case noSupportedFields
}

/// Parses a vCard 3.0 or 4.0 payload into provider-neutral field suggestions.
public struct VCardParser: Sendable {
  public init() {}

  public func parse(_ payload: String) throws -> CardFieldResult {
    let properties = try properties(in: payload)
    var result = CardFieldResult(ruleVersions: ["vcard-1.0.0"])
    var structuredName: String?

    for (index, property) in properties.enumerated() {
      let source = ["vcard:\(String(format: "%04d", index + 1)):\(property.name)"]
      switch property.name {
      case "FN":
        assignSingular(
          value(property.value, source: source),
          to: &result.fullName
        )
      case "N":
        structuredName = displayName(from: property.components)
      case "ORG":
        assignSingular(
          value(property.components.joined(separator: " "), source: source),
          to: &result.organization
        )
      case "TITLE":
        assignSingular(value(property.value, source: source), to: &result.jobTitle)
      case "EMAIL":
        if isEmail(property.value) {
          result.emailAddresses.append(value(property.value.lowercased(), source: source))
        }
      case "TEL":
        guard isPhone(property.value) else { continue }
        let phone = value(property.value, source: source)
        let types = property.types
        if types.contains("FAX") {
          result.faxNumbers.append(phone)
        } else if !types.isDisjoint(with: ["CELL", "MOBILE"]) {
          result.mobilePhoneNumbers.append(phone)
        } else {
          result.workPhoneNumbers.append(phone)
        }
      case "ADR":
        let address = displayAddress(from: property.components)
        if !address.isEmpty {
          result.addresses.append(value(address, source: source))
        }
      case "URL":
        if isURL(property.value) {
          result.websites.append(value(property.value, source: source))
        }
      default:
        continue
      }
    }

    if result.fullName == nil, let structuredName, !structuredName.isEmpty {
      result.fullName = value(structuredName, source: ["vcard:N"])
    }
    result = CardScanSession().canonicalized(result)
    guard !result.allClassifiedValues.isEmpty else {
      throw VCardParsingError.noSupportedFields
    }
    return result
  }

  public func parse(_ data: Data) throws -> CardFieldResult {
    guard let payload = Self.decode(data) else {
      throw VCardParsingError.unsupportedEncoding
    }
    return try parse(payload)
  }

  private static func decode(_ data: Data) -> String? {
    if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
    let eucKR = String.Encoding(rawValue: 0x8000_0940)
    return String(data: data, encoding: eucKR)
  }

  private func properties(in payload: String) throws -> [Property] {
    let unfolded = unfold(payload)
    guard unfolded.first?.uppercased() == "BEGIN:VCARD",
      unfolded.last?.uppercased() == "END:VCARD"
    else {
      throw VCardParsingError.invalidEnvelope
    }
    let version = unfolded.first { $0.uppercased().hasPrefix("VERSION:") }?
      .split(separator: ":", maxSplits: 1).last.map(String.init)
    guard version == "3.0" || version == "4.0" else {
      throw VCardParsingError.unsupportedVersion
    }

    return unfolded.dropFirst().dropLast().compactMap(parseProperty)
  }

  private func unfold(_ payload: String) -> [String] {
    let normalized = payload.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var lines: [String] = []
    for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      if line.hasPrefix(" ") || line.hasPrefix("\t"), !lines.isEmpty {
        lines[lines.count - 1] += line.dropFirst()
      } else if lines.last?.hasSuffix("=") == true {
        lines[lines.count - 1].removeLast()
        lines[lines.count - 1] += line
      } else if !line.isEmpty {
        lines.append(line)
      }
    }
    return lines
  }

  private func parseProperty(_ line: String) -> Property? {
    guard let colon = firstUnescapedColon(in: line) else { return nil }
    let header = String(line[..<colon])
    let rawValue = String(line[line.index(after: colon)...])
    let parts = header.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
    guard let rawName = parts.first else { return nil }
    let name = rawName.split(separator: ".").last.map(String.init)?.uppercased() ?? ""
    var parameters: [String: String] = [:]
    var unlabeledTypes: [String] = []
    for part in parts.dropFirst() {
      let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
      if pair.count == 2 {
        parameters[pair[0].uppercased()] = pair[1]
      } else {
        unlabeledTypes.append(part)
      }
    }
    let decoded =
      parameters["ENCODING"]?.uppercased() == "QUOTED-PRINTABLE"
      ? decodeQuotedPrintable(rawValue, charset: parameters["CHARSET"]) : rawValue
    let types = Set(
      ((parameters["TYPE"] ?? "").split(separator: ",").map(String.init) + unlabeledTypes)
        .map { $0.uppercased() }
    )
    return Property(
      name: name,
      value: unescape(decoded),
      components: splitStructuredValue(decoded),
      types: types
    )
  }

  private func firstUnescapedColon(in line: String) -> String.Index? {
    var escaped = false
    for index in line.indices {
      let character = line[index]
      if character == ":" && !escaped { return index }
      if character == "\\" && !escaped {
        escaped = true
      } else {
        escaped = false
      }
    }
    return nil
  }

  private func decodeQuotedPrintable(_ value: String, charset: String?) -> String {
    var bytes: [UInt8] = []
    let scalars = Array(value.unicodeScalars)
    var index = 0
    while index < scalars.count {
      if scalars[index] == "=", index + 2 < scalars.count,
        let byte = UInt8(
          String(scalars[index + 1]) + String(scalars[index + 2]),
          radix: 16
        )
      {
        bytes.append(byte)
        index += 3
      } else {
        bytes.append(contentsOf: String(scalars[index]).utf8)
        index += 1
      }
    }
    let encoding =
      charset?.uppercased().contains("EUC-KR") == true
      ? String.Encoding(rawValue: 0x8000_0940) : .utf8
    return String(bytes: bytes, encoding: encoding) ?? value
  }

  private func unescape(_ value: String) -> String {
    var output = ""
    var escaped = false
    for character in value {
      if escaped {
        switch character {
        case "n", "N": output.append("\n")
        case ",": output.append(",")
        case ";": output.append(";")
        case "\\": output.append("\\")
        default:
          output.append("\\")
          output.append(character)
        }
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else {
        output.append(character)
      }
    }
    if escaped { output.append("\\") }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func splitStructuredValue(_ value: String) -> [String] {
    var components: [String] = []
    var current = ""
    var escaped = false
    for character in value {
      if character == ";" && !escaped {
        components.append(unescape(current))
        current = ""
      } else {
        current.append(character)
      }
      if character == "\\" && !escaped {
        escaped = true
      } else {
        escaped = false
      }
    }
    components.append(unescape(current))
    return components
  }

  private func displayName(from components: [String]) -> String {
    guard !components.isEmpty else { return "" }
    let family = components[0]
    let given = components.count > 1 ? components[1] : ""
    let additional = components.count > 2 ? components[2] : ""
    let prefix = components.count > 3 ? components[3] : ""
    let suffix = components.count > 4 ? components[4] : ""
    return [prefix, given, additional, family, suffix]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private func displayAddress(from components: [String]) -> String {
    let preferred =
      components.count >= 7
      ? [components[2], components[3], components[4], components[5], components[6]]
      : components
    return preferred.filter { !$0.isEmpty }.joined(separator: ", ")
  }

  private func value(_ text: String, source: [String]) -> ClassifiedValue {
    ClassifiedValue(
      normalizedValue: text,
      originalValue: text,
      confidence: 0.995,
      evidence: [.syntaxMatch],
      sourceTokenIdentifiers: source
    )
  }

  private func assignSingular(_ value: ClassifiedValue, to target: inout ClassifiedValue?) {
    if target == nil { target = value }
  }

  private func isEmail(_ value: String) -> Bool {
    value.range(
      of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,
      options: .regularExpression
    ) != nil
  }

  private func isPhone(_ value: String) -> Bool {
    let digits = value.filter(\.isNumber)
    return digits.count >= 7 && digits.count <= 18
  }

  private func isURL(_ value: String) -> Bool {
    let lower = value.lowercased()
    if lower.hasPrefix("www.") { return lower.dropFirst(4).contains(".") }
    guard let components = URLComponents(string: value),
      components.scheme == "http" || components.scheme == "https"
    else { return false }
    return components.host?.contains(".") == true
  }

  private struct Property {
    var name: String
    var value: String
    var components: [String]
    var types: Set<String>
  }
}

/// The front, optional back, and deterministic merged suggestions for one physical card.
public struct MergedCardResult: Codable, Equatable, Sendable {
  public var front: CardFieldResult
  public var back: CardFieldResult?
  public var merged: CardFieldResult

  public init(front: CardFieldResult, back: CardFieldResult?, merged: CardFieldResult) {
    self.front = front
    self.back = back
    self.merged = merged
  }
}

/// Combines front and back suggestions without persisting images or contact data.
public struct CardScanSession: Sendable {
  public init() {}

  public func merge(front: CardFieldResult, back: CardFieldResult?) -> MergedCardResult {
    guard let back else {
      return MergedCardResult(front: front, back: nil, merged: canonicalized(front))
    }
    var result = front
    result.ruleVersions = Array(Set(front.ruleVersions + back.ruleVersions)).sorted()
    var fullNameConflict = false
    var preferredNameConflict = false
    var jobTitleConflict = false
    var departmentConflict = false
    var organizationConflict = false

    result.fullName = mergeSingular(
      front.fullName,
      back.fullName,
      conflict: &fullNameConflict
    )
    result.preferredName = mergeSingular(
      front.preferredName,
      back.preferredName,
      conflict: &preferredNameConflict
    )
    result.jobTitle = mergeSingular(
      front.jobTitle,
      back.jobTitle,
      conflict: &jobTitleConflict
    )
    result.department = mergeSingular(
      front.department,
      back.department,
      conflict: &departmentConflict
    )
    result.organization = mergeSingular(
      front.organization,
      back.organization,
      conflict: &organizationConflict
    )
    result.alternateNames = mergeValues(front.alternateNames, back.alternateNames, phone: false)
    result.emailAddresses = mergeValues(front.emailAddresses, back.emailAddresses, phone: false)
    let phones = mergePhoneFamilies(front: front, back: back)
    result.mobilePhoneNumbers = phones.mobile
    result.workPhoneNumbers = phones.work
    result.faxNumbers = phones.fax
    result.websites = mergeValues(front.websites, back.websites, phone: false)
    result.professionalProfileURLs = mergeValues(
      front.professionalProfileURLs, back.professionalProfileURLs, phone: false)
    result.socialHandles = mergeValues(front.socialHandles, back.socialHandles, phone: false)
    result.addresses = mergeValues(front.addresses, back.addresses, phone: false)
    result.unclassifiedLines = mergeUnclassified(front.unclassifiedLines, back.unclassifiedLines)
    result.warnings = Array(Set(front.warnings + back.warnings)).sorted {
      $0.rawValue < $1.rawValue
    }
    let hasReviewConflict =
      fullNameConflict || preferredNameConflict || jobTitleConflict || departmentConflict
      || organizationConflict
    let hasIdentityConflict = fullNameConflict || preferredNameConflict
    if hasReviewConflict {
      result.warnings.append(.reviewRecommended)
    }
    if hasIdentityConflict {
      result.warnings.append(.identityConflict)
    }
    if hasReviewConflict || hasIdentityConflict {
      result.warnings = Array(Set(result.warnings))
        .sorted { $0.rawValue < $1.rawValue }
    }
    result = canonicalized(result)
    return MergedCardResult(front: front, back: back, merged: result)
  }

  func canonicalized(_ input: CardFieldResult) -> CardFieldResult {
    var result = input
    result.alternateNames = mergeValues([], result.alternateNames, phone: false)
    result.emailAddresses = mergeValues([], result.emailAddresses, phone: false)
    let phones = mergePhoneFamilies(front: result, back: CardFieldResult())
    result.mobilePhoneNumbers = phones.mobile
    result.workPhoneNumbers = phones.work
    result.faxNumbers = phones.fax
    result.websites = mergeValues([], result.websites, phone: false)
    result.professionalProfileURLs = mergeValues([], result.professionalProfileURLs, phone: false)
    result.socialHandles = mergeValues([], result.socialHandles, phone: false)
    result.addresses = mergeValues([], result.addresses, phone: false)
    let confidences = result.allClassifiedValues.map(\.confidence)
    result.overallConfidence =
      confidences.isEmpty
      ? 0 : confidences.reduce(0, +) / Double(confidences.count)
    result.warnings = Array(Set(result.warnings)).sorted { $0.rawValue < $1.rawValue }
    return result
  }

  private func mergeSingular(
    _ front: ClassifiedValue?,
    _ back: ClassifiedValue?,
    conflict: inout Bool
  ) -> ClassifiedValue? {
    guard let front else { return back }
    guard let back else { return front }
    if identityKey(front, phone: false) == identityKey(back, phone: false) {
      return preferred(front, back)
    }
    conflict = true
    let winner = isBarcode(back) ? back : front
    let loser = winner == front ? back : front
    var merged = winner
    let candidate = AlternativeCandidate(
      normalizedValue: loser.normalizedValue,
      originalValue: loser.originalValue,
      confidence: loser.confidence,
      evidence: loser.evidence,
      sourceTokenIdentifiers: loser.sourceTokenIdentifiers
    )
    merged.alternativeCandidates = (merged.alternativeCandidates + [candidate])
      .sorted { $0.normalizedValue.cardFieldFolded < $1.normalizedValue.cardFieldFolded }
    return merged
  }

  private func mergeValues(
    _ front: [ClassifiedValue],
    _ back: [ClassifiedValue],
    phone: Bool
  ) -> [ClassifiedValue] {
    var grouped: [String: ClassifiedValue] = [:]
    for value in front + back {
      let key = identityKey(value, phone: phone)
      guard !key.isEmpty else { continue }
      if let existing = grouped[key] {
        grouped[key] = preferred(existing, value)
      } else {
        grouped[key] = value
      }
    }
    return grouped.sorted { lhs, rhs in lhs.key < rhs.key }.map(\.value)
  }

  private func mergePhoneFamilies(
    front: CardFieldResult,
    back: CardFieldResult
  ) -> (mobile: [ClassifiedValue], work: [ClassifiedValue], fax: [ClassifiedValue]) {
    let candidates =
      phoneCandidates(in: front, side: 0) + phoneCandidates(in: back, side: 1)
    var grouped: [String: PhoneCandidate] = [:]
    for candidate in candidates {
      let key = identityKey(candidate.value, phone: true)
      guard !key.isEmpty else { continue }
      if let existing = grouped[key] {
        grouped[key] = preferredPhone(existing, candidate)
      } else {
        grouped[key] = candidate
      }
    }
    let selected = grouped.sorted { $0.key < $1.key }.map(\.value)
    return (
      selected.filter { $0.family == .mobile }.map(\.value),
      selected.filter { $0.family == .work }.map(\.value),
      selected.filter { $0.family == .fax }.map(\.value)
    )
  }

  private func phoneCandidates(in result: CardFieldResult, side: Int) -> [PhoneCandidate] {
    result.mobilePhoneNumbers.map { PhoneCandidate(value: $0, family: .mobile, side: side) }
      + result.workPhoneNumbers.map { PhoneCandidate(value: $0, family: .work, side: side) }
      + result.faxNumbers.map { PhoneCandidate(value: $0, family: .fax, side: side) }
  }

  private func preferredPhone(_ lhs: PhoneCandidate, _ rhs: PhoneCandidate) -> PhoneCandidate {
    if isBarcode(lhs.value) != isBarcode(rhs.value) {
      return isBarcode(lhs.value) ? lhs : rhs
    }
    if lhs.value.confidence != rhs.value.confidence {
      return lhs.value.confidence > rhs.value.confidence ? lhs : rhs
    }
    if lhs.side != rhs.side { return lhs.side > rhs.side ? lhs : rhs }
    if lhs.family != rhs.family { return lhs.family.rank < rhs.family.rank ? lhs : rhs }
    return preferred(lhs.value, rhs.value) == lhs.value ? lhs : rhs
  }

  private func preferred(_ lhs: ClassifiedValue, _ rhs: ClassifiedValue) -> ClassifiedValue {
    if isBarcode(lhs) != isBarcode(rhs) { return isBarcode(lhs) ? lhs : rhs }
    if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence ? lhs : rhs }
    if lhs.normalizedValue != rhs.normalizedValue {
      return lhs.normalizedValue < rhs.normalizedValue ? lhs : rhs
    }
    return lhs.sourceTokenIdentifiers.lexicographicallyPrecedes(rhs.sourceTokenIdentifiers)
      ? lhs : rhs
  }

  private func identityKey(_ value: ClassifiedValue, phone: Bool) -> String {
    if phone { return value.normalizedValue.filter(\.isNumber) }
    return value.normalizedValue.cardFieldIdentityKey
  }

  private func isBarcode(_ value: ClassifiedValue) -> Bool {
    value.sourceTokenIdentifiers.contains {
      $0.hasPrefix("vcard:") || $0.hasPrefix("barcode:")
    }
  }

  private func mergeUnclassified(_ lhs: [OCRToken], _ rhs: [OCRToken]) -> [OCRToken] {
    var grouped: [String: OCRToken] = [:]
    for token in lhs + rhs {
      let key = token.text.cardFieldIdentityKey
      if let existing = grouped[key] {
        if token.confidence > existing.confidence { grouped[key] = token }
      } else if !key.isEmpty {
        grouped[key] = token
      }
    }
    return OCRNormalizer.normalize(Array(grouped.values))
  }

  private enum PhoneFamily {
    case mobile
    case work
    case fax

    var rank: Int {
      switch self {
      case .mobile: 0
      case .fax: 1
      case .work: 2
      }
    }
  }

  private struct PhoneCandidate {
    var value: ClassifiedValue
    var family: PhoneFamily
    var side: Int
  }
}

extension CardFieldResult {
  fileprivate var allClassifiedValues: [ClassifiedValue] {
    [fullName, preferredName, jobTitle, department, organization].compactMap { $0 }
      + alternateNames + emailAddresses + mobilePhoneNumbers + workPhoneNumbers + faxNumbers
      + websites + professionalProfileURLs + socialHandles + addresses
  }
}
