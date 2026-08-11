import Foundation

public struct CardFieldClassifier: Sendable {
  private let rulePacks: [RulePack]
  private let correctionStore: any CorrectionStore

  public init(
    rulePacks: [RulePack] = [],
    correctionStore: any CorrectionStore = EmptyCorrectionStore()
  ) {
    self.rulePacks = rulePacks
    self.correctionStore = correctionStore
  }

  public func classify(_ observations: [OCRToken]) throws -> CardFieldResult {
    let tokens = OCRNormalizer.normalize(observations)
    let corrections = try correctionStore.loadCorrections().sorted { $0.id < $1.id }
    var rules = EffectiveRules(packs: rulePacks)
    applyVocabularyCorrections(corrections, to: &rules)

    guard !tokens.isEmpty else {
      return CardFieldResult(
        ruleVersions: rules.versions,
        warnings: [.emptyInput, .noVisiblePersonName]
      )
    }

    var consumed = Set<String>()
    var result = CardFieldResult(ruleVersions: rules.versions)
    if tokens.contains(where: { !$0.boundingBox.isValid }) {
      result.warnings.append(.invalidBoundingBox)
    }

    result.emailAddresses = extractEmails(tokens, consumed: &consumed)
    let phoneResults = extractPhones(
      tokens, rules: rules, corrections: corrections, consumed: &consumed)
    result.mobilePhoneNumbers = phoneResults.mobile
    result.workPhoneNumbers = phoneResults.work
    result.faxNumbers = phoneResults.fax
    if phoneResults.hasAmbiguousNumber {
      result.warnings.append(.ambiguousPhoneNumber)
    }
    let webResults = extractWebValues(tokens, consumed: &consumed)
    result.websites = webResults.websites
    result.professionalProfileURLs = webResults.profiles
    result.socialHandles = webResults.handles

    let expanded = expandedIdentityLines(tokens, rules: rules)
    result.jobTitle = bestJobTitle(expanded, rules: rules, excluding: consumed)
    if let jobTitle = result.jobTitle {
      consumed.formUnion(jobTitle.sourceTokenIdentifiers)
    }
    result.department = bestDepartment(expanded, rules: rules, excluding: consumed)
    if let department = result.department {
      consumed.formUnion(department.sourceTokenIdentifiers)
    }
    result.addresses = extractAddresses(expanded, rules: rules, excluding: consumed)
    for address in result.addresses {
      consumed.formUnion(address.sourceTokenIdentifiers)
    }

    let domainHint = result.emailAddresses.first?.normalizedValue
      .split(separator: "@").last.map(String.init)
    let organizationCandidates = organizationCandidates(
      expanded,
      rules: rules,
      emailDomain: domainHint,
      excluding: consumed
    )
    result.organization = organizationCandidates.first?.value
    if let organization = result.organization {
      consumed.formUnion(organization.sourceTokenIdentifiers)
    }

    let names = nameCandidates(
      expanded,
      rules: rules,
      emailLocalPart: result.emailAddresses.first?.normalizedValue.split(separator: "@").first.map(
        String.init),
      excluding: consumed
    )
    if let first = names.first, first.value.confidence >= 0.66 {
      result.fullName = withAlternatives(first, from: Array(names.dropFirst()))
      consumed.formUnion(first.value.sourceTokenIdentifiers)
      result.alternateNames = names.dropFirst().filter { candidate in
        candidate.value.confidence >= 0.66
          && candidate.value.sourceTokenIdentifiers != first.value.sourceTokenIdentifiers
      }.map(\.value)
      for alternateName in result.alternateNames {
        consumed.formUnion(alternateName.sourceTokenIdentifiers)
      }
      if names.dropFirst().first?.value.confidence ?? 0 >= first.value.confidence - 0.05 {
        result.warnings.append(.ambiguousPersonName)
      }
    } else {
      result.warnings.append(.noVisiblePersonName)
    }

    applyReclassificationCorrections(
      corrections,
      tokens: expanded,
      result: &result,
      consumed: &consumed
    )
    applyOrganizationCorrections(
      corrections,
      emailDomain: domainHint,
      tokens: expanded,
      result: &result,
      consumed: &consumed
    )
    applyPreferredNameCorrections(corrections, result: &result)

    result.unclassifiedLines = tokens.filter { !consumed.contains($0.id) }
    let confidences = allValues(in: result).map(\.confidence)
    result.overallConfidence =
      confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
    if confidences.contains(where: { $0 < 0.72 }) {
      result.warnings.append(.lowConfidenceFields)
    }
    result.warnings = Array(Set(result.warnings)).sorted { $0.rawValue < $1.rawValue }
    return result
  }
}

extension CardFieldClassifier {
  fileprivate struct InternalCandidate {
    var value: ClassifiedValue
    var position: Int
  }

  fileprivate struct WorkingLine {
    var text: String
    var token: OCRToken
    var position: Int
  }

  fileprivate func expandedIdentityLines(_ tokens: [OCRToken], rules: EffectiveRules)
    -> [WorkingLine]
  {
    tokens.enumerated().flatMap { position, token in
      for separator in ["|", "/", "·"] {
        let parts = token.text.split(separator: Character(separator), maxSplits: 1)
        if parts.count == 2 {
          let lhs = parts[0].trimmingCharacters(in: .whitespaces)
          let rhs = parts[1].trimmingCharacters(in: .whitespaces)
          if isNameLike(lhs, rules: rules), isJobTitleLike(rhs, rules: rules) {
            return [
              WorkingLine(text: lhs, token: token, position: position),
              WorkingLine(text: rhs, token: token, position: position),
            ]
          }
        }
      }
      return [WorkingLine(text: token.text, token: token, position: position)]
    }
  }

  fileprivate func extractEmails(_ tokens: [OCRToken], consumed: inout Set<String>)
    -> [ClassifiedValue]
  {
    let pattern = #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#
    return regexValues(pattern, tokens: tokens, options: [.caseInsensitive]).map { match in
      consumed.insert(match.token.id)
      return ClassifiedValue(
        normalizedValue: match.value.lowercased(),
        originalValue: match.value,
        confidence: 0.72 + match.token.confidence * 0.26,
        evidence: [.syntaxMatch],
        sourceTokenIdentifiers: [match.token.id]
      )
    }.uniqued()
  }

  fileprivate func extractPhones(
    _ tokens: [OCRToken],
    rules: EffectiveRules,
    corrections: [PersonalCorrection],
    consumed: inout Set<String>
  ) -> (
    mobile: [ClassifiedValue], work: [ClassifiedValue], fax: [ClassifiedValue],
    hasAmbiguousNumber: Bool
  ) {
    let matches = regexValues(#"(?:\+?\d[\d ()\-.]{5,}\d)"#, tokens: tokens)
    var values: [PhoneKind: [ClassifiedValue]] = [:]
    var hasAmbiguousNumber = false
    for match in matches where match.value.filter(\.isNumber).count >= 7 {
      let prefix = String(match.token.text.prefix(upTo: match.range.lowerBound))
        .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":.-|")))
        .cardFieldFolded
      guard var kind = matchedPhoneKind(prefix: prefix, rules: rules) else {
        hasAmbiguousNumber = true
        continue
      }
      var evidence: [Evidence] = kind == .mobile ? [.precededByMobileLabel] : [.precededByWorkLabel]
      if kind == .fax { evidence = [.precededByFaxLabel] }
      if let correction = corrections.first(where: {
        $0.kind == .phoneLabelInterpretation && $0.match.cardFieldFolded == prefix
          && $0.phoneKind != nil
      }), let correctedKind = correction.phoneKind {
        kind = correctedKind
        evidence.append(.userCorrection)
      }
      consumed.insert(match.token.id)
      let trimmed = match.value.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;"))
      let normalized = trimmed.filter { $0.isNumber || $0 == "+" }
      let classified = ClassifiedValue(
        normalizedValue: normalized,
        originalValue: trimmed,
        confidence: 0.68 + match.token.confidence * 0.27,
        evidence: evidence,
        sourceTokenIdentifiers: [match.token.id]
      )
      values[kind, default: []].append(classified)
    }
    return (
      values[.mobile, default: []].uniqued(),
      values[.work, default: []].uniqued(),
      values[.fax, default: []].uniqued(),
      hasAmbiguousNumber
    )
  }

  fileprivate func matchedPhoneKind(prefix: String, rules: EffectiveRules) -> PhoneKind? {
    let lastWord = prefix.components(separatedBy: CharacterSet.alphanumerics.inverted)
      .last(where: { !$0.isEmpty })
    return rules.phoneLabels.sorted { lhs, rhs in
      if lhs.key.count != rhs.key.count { return lhs.key.count > rhs.key.count }
      return lhs.key < rhs.key
    }.first(where: { label, _ in
      prefix == label || lastWord == label
        || (label.unicodeScalars.contains(where: { $0.value > 127 }) && prefix.hasSuffix(label))
    })?.value
  }

  fileprivate func extractWebValues(
    _ tokens: [OCRToken],
    consumed: inout Set<String>
  ) -> (websites: [ClassifiedValue], profiles: [ClassifiedValue], handles: [ClassifiedValue]) {
    let domains = regexValues(
      #"\b(?:https?://|www\.)?(?:[A-Z0-9\-]+\.)+[A-Z]{2,}(?:/[^\s]*)?\b"#,
      tokens: tokens,
      options: [.caseInsensitive]
    ).filter { !$0.token.text.contains("@") }
    var websites: [ClassifiedValue] = []
    var profiles: [ClassifiedValue] = []
    for match in domains {
      consumed.insert(match.token.id)
      let normalized = match.value.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: ".,"))
      let isProfile = ["linkedin.com/", "github.com/", "x.com/", "behance.net/"].contains {
        normalized.contains($0)
      }
      let value = ClassifiedValue(
        normalizedValue: normalized,
        originalValue: match.value,
        confidence: 0.70 + match.token.confidence * 0.26,
        evidence: isProfile ? [.syntaxMatch, .profileHost] : [.syntaxMatch],
        sourceTokenIdentifiers: [match.token.id]
      )
      if isProfile { profiles.append(value) } else { websites.append(value) }
    }
    let handles = regexValues(
      #"(?<![A-Z0-9._%+\-])@[A-Z0-9_\.]{2,}"#, tokens: tokens, options: [.caseInsensitive]
    )
    .filter { $0.token.text.trimmingCharacters(in: .whitespaces).hasPrefix("@") }
    .map { match in
      consumed.insert(match.token.id)
      return ClassifiedValue(
        normalizedValue: match.value.lowercased(),
        originalValue: match.value,
        confidence: 0.68 + match.token.confidence * 0.25,
        evidence: [.socialPrefix],
        sourceTokenIdentifiers: [match.token.id]
      )
    }
    return (websites.uniqued(), profiles.uniqued(), handles.uniqued())
  }

  fileprivate func bestJobTitle(
    _ lines: [WorkingLine],
    rules: EffectiveRules,
    excluding: Set<String>
  ) -> ClassifiedValue? {
    lines.filter { !excluding.contains($0.token.id) && isJobTitleLike($0.text, rules: rules) }
      .filter { line in
        !isOrganizationLike(line.text, rules: rules)
          || ["senior", "principal", "lead", "선임", "책임", "수석"].contains {
            line.text.cardFieldFolded.contains($0)
          }
      }
      .map { line in
        InternalCandidate(
          value: value(
            line,
            confidence: 0.65 + line.token.confidence * 0.25,
            evidence: [.titleVocabulary] + packEvidence(for: line.text, rules: rules)
          ),
          position: line.position
        )
      }.sorted(by: candidateOrder).first?.value
  }

  fileprivate func bestDepartment(
    _ lines: [WorkingLine],
    rules: EffectiveRules,
    excluding: Set<String>
  ) -> ClassifiedValue? {
    lines.filter {
      !excluding.contains($0.token.id) && rules.contains(rules.departmentTerms, in: $0.text)
        && !isOrganizationLike($0.text, rules: rules)
    }.map { line in
      InternalCandidate(
        value: value(
          line,
          confidence: 0.58 + line.token.confidence * 0.25,
          evidence: [.departmentVocabulary] + packEvidence(for: line.text, rules: rules)
        ),
        position: line.position
      )
    }.sorted(by: candidateOrder).first?.value
  }

  fileprivate func extractAddresses(
    _ lines: [WorkingLine],
    rules: EffectiveRules,
    excluding: Set<String>
  ) -> [ClassifiedValue] {
    lines.filter { !excluding.contains($0.token.id) && isAddressLike($0.text, rules: rules) }
      .map {
        value(
          $0,
          confidence: 0.56 + $0.token.confidence * 0.28,
          evidence: [.addressVocabulary] + packEvidence(for: $0.text, rules: rules)
        )
      }
      .uniqued()
  }

  fileprivate func organizationCandidates(
    _ lines: [WorkingLine],
    rules: EffectiveRules,
    emailDomain: String?,
    excluding: Set<String>
  ) -> [InternalCandidate] {
    lines.compactMap { line in
      guard !excluding.contains(line.token.id), isOrganizationLike(line.text, rules: rules) else {
        return nil
      }
      var score = 0.49 + line.token.confidence * 0.24
      var evidence: [Evidence] = []
      let folded = line.text.cardFieldFolded
      if rules.contains(rules.organizationSuffixes, in: folded) {
        score += 0.16
        evidence.append(.organizationSuffix)
      }
      if rules.contains(rules.organizationTerms, in: folded) || isUppercaseBrand(line.text) {
        score += 0.13
        evidence.append(.organizationVocabulary)
      }
      if let root = emailDomain?.split(separator: ".").first.map(String.init),
        folded.cardFieldIdentityKey.contains(root.cardFieldIdentityKey)
      {
        score += 0.10
        evidence.append(.emailDomainHint)
      }
      if line.token.boundingBox.height >= 0.07 {
        score += 0.06
        evidence.append(.layoutProminence)
      }
      evidence.append(contentsOf: packEvidence(for: line.text, rules: rules))
      return InternalCandidate(
        value: value(line, confidence: min(score, 0.98), evidence: evidence),
        position: line.position)
    }.sorted(by: candidateOrder)
  }

  fileprivate func nameCandidates(
    _ lines: [WorkingLine],
    rules: EffectiveRules,
    emailLocalPart: String?,
    excluding: Set<String>
  ) -> [InternalCandidate] {
    lines.compactMap { line in
      // A name and role may share one source observation, so a consumed token can
      // still contribute a distinct, conservatively validated identity segment.
      guard isNameLike(line.text, rules: rules) else { return nil }
      var score = 0.43 + line.token.confidence * 0.20
      var evidence: [Evidence] = []
      if line.position == 0 { score += 0.08 }
      if line.token.boundingBox.height >= 0.055 {
        score += 0.10
        evidence.append(.layoutProminence)
      }
      if let emailLocalPart, emailMatchesName(emailLocalPart, name: line.text) {
        score += 0.17
        evidence.append(.matchesEmailLocalPart)
      }
      if lines.contains(where: {
        $0.position >= line.position && $0.position <= line.position + 1
          && $0.token.id != line.token.id && isJobTitleLike($0.text, rules: rules)
      }) {
        score += 0.10
        evidence.append(.nearJobTitle)
      }
      if containsCJK(line.text) && containsLatin(line.text) {
        score += 0.06
        evidence.append(.multilingualVariant)
      }
      return InternalCandidate(
        value: value(line, confidence: min(score, 0.96), evidence: evidence),
        position: line.position)
    }.sorted(by: candidateOrder)
  }

  fileprivate func isNameLike(_ text: String, rules: EffectiveRules) -> Bool {
    let components = text.split(whereSeparator: \Character.isWhitespace).map(String.init)
    guard (1...7).contains(components.count), text.count <= 90 else { return false }
    guard text.range(of: #"[0-9@:/,.]"#, options: .regularExpression) == nil else { return false }
    guard !isJobTitleLike(text, rules: rules), !isOrganizationLike(text, rules: rules),
      !isAddressLike(text, rules: rules), !isSloganLike(text, rules: rules)
    else { return false }

    if containsCJK(text) && containsLatin(text) { return true }
    if components.count == 1 {
      let scalars = text.unicodeScalars
      if scalars.count >= 2 && scalars.count <= 4 && scalars.allSatisfy(isCJKScalar) { return true }
      return isCapitalizedLatinNameToken(text)
    }
    let connectors: Set<String> = [
      "da", "de", "del", "della", "di", "dos", "du", "la", "le", "van", "von", "y",
    ]
    let uppercaseCount = components.filter { component in
      component.count > 1 && component == component.uppercased()
        && component.range(of: #"^[A-Z\-']+$"#, options: .regularExpression) != nil
    }.count
    guard uppercaseCount <= 1 else { return false }
    return components.allSatisfy {
      connectors.contains($0.cardFieldFolded) || isCapitalizedLatinNameToken($0)
        || $0.unicodeScalars.allSatisfy(isCJKScalar)
    }
  }

  fileprivate func isJobTitleLike(_ text: String, rules: EffectiveRules) -> Bool {
    rules.contains(rules.jobTitles, in: text)
  }

  fileprivate func isOrganizationLike(_ text: String, rules: EffectiveRules) -> Bool {
    guard !isSloganLike(text, rules: rules) else { return false }
    let folded = text.cardFieldFolded
    if rules.contains(rules.organizationSuffixes, in: folded)
      || rules.contains(rules.organizationTerms, in: folded)
    {
      return true
    }
    if isUppercaseBrand(text) { return true }
    let hasDigit = text.contains(where: \.isNumber)
    let hasBrandLetters = text.filter(\.isLetter).count >= 2
    return hasDigit && hasBrandLetters && !isAddressLike(text, rules: rules)
  }

  fileprivate func isAddressLike(_ text: String, rules: EffectiveRules) -> Bool {
    let digitCount = text.filter(\.isNumber).count
    let hasAddressTerm = rules.contains(rules.addressTerms, in: text)
    let postalPattern =
      text.range(of: #"\b\d{3,6}(?:-\d{3,4})?\b"#, options: .regularExpression) != nil
    return hasAddressTerm && (digitCount > 0 || postalPattern)
  }

  fileprivate func isSloganLike(_ text: String, rules: EffectiveRules) -> Bool {
    rules.contains(rules.sloganTerms, in: text)
      || (text.split(separator: " ").count >= 4 && text.hasSuffix("!"))
  }

  fileprivate func isUppercaseBrand(_ text: String) -> Bool {
    guard containsLatin(text) else { return false }
    let letters = text.filter(\.isLetter)
    guard letters.count >= 2 else { return false }
    return String(letters) == String(letters).uppercased() && text.split(separator: " ").count <= 6
  }

  fileprivate func isCapitalizedLatinNameToken(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "-'"))
    guard trimmed.count >= 2,
      trimmed.unicodeScalars.allSatisfy({
        CharacterSet.letters.contains($0) || $0 == "-" || $0 == "'"
      })
    else { return false }
    guard let first = trimmed.unicodeScalars.first,
      CharacterSet.uppercaseLetters.contains(first)
    else { return false }
    return trimmed.unicodeScalars.dropFirst().contains {
      CharacterSet.lowercaseLetters.contains($0)
    }
  }

  fileprivate func containsCJK(_ text: String) -> Bool {
    text.unicodeScalars.contains(where: isCJKScalar)
  }
  fileprivate func containsLatin(_ text: String) -> Bool {
    text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
  }

  fileprivate func emailMatchesName(_ localPart: String, name: String) -> Bool {
    let localKey = localPart.cardFieldIdentityKey
    let nameKey = name.cardFieldIdentityKey
    if localKey.contains(nameKey) || nameKey.contains(localKey) { return true }
    let nameParts = name.components(separatedBy: CharacterSet.letters.inverted)
      .map(\.cardFieldIdentityKey)
      .filter { $0.count >= 2 }
    return nameParts.filter { localKey.contains($0) }.count >= 2
  }

  fileprivate func packEvidence(for text: String, rules: EffectiveRules) -> [Evidence] {
    var evidence: [Evidence] = []
    if rules.contains(rules.localeTerms, in: text) { evidence.append(.localeRulePack) }
    if rules.contains(rules.industryTerms, in: text) { evidence.append(.industryRulePack) }
    return evidence
  }

  fileprivate func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
    (0x3040...0x30FF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
      || (0x4E00...0x9FFF).contains(scalar.value) || (0xAC00...0xD7A3).contains(scalar.value)
  }

  fileprivate func value(_ line: WorkingLine, confidence: Double, evidence: [Evidence])
    -> ClassifiedValue
  {
    ClassifiedValue(
      normalizedValue: line.text.trimmingCharacters(in: .whitespacesAndNewlines),
      originalValue: line.text,
      confidence: confidence,
      evidence: evidence,
      sourceTokenIdentifiers: [line.token.id]
    )
  }

  fileprivate func candidateOrder(_ lhs: InternalCandidate, _ rhs: InternalCandidate) -> Bool {
    if lhs.value.confidence != rhs.value.confidence {
      return lhs.value.confidence > rhs.value.confidence
    }
    if lhs.position != rhs.position { return lhs.position < rhs.position }
    return lhs.value.normalizedValue < rhs.value.normalizedValue
  }

  fileprivate func withAlternatives(_ primary: InternalCandidate, from others: [InternalCandidate])
    -> ClassifiedValue
  {
    var value = primary.value
    value.alternativeCandidates = others.prefix(3).map { candidate in
      AlternativeCandidate(
        normalizedValue: candidate.value.normalizedValue,
        originalValue: candidate.value.originalValue,
        confidence: candidate.value.confidence,
        evidence: candidate.value.evidence,
        sourceTokenIdentifiers: candidate.value.sourceTokenIdentifiers
      )
    }
    return value
  }
}

extension CardFieldClassifier {
  fileprivate struct RegexMatch {
    var value: String
    var token: OCRToken
    var range: Range<String.Index>
  }

  fileprivate func regexValues(
    _ pattern: String,
    tokens: [OCRToken],
    options: NSRegularExpression.Options = []
  ) -> [RegexMatch] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
      return []
    }
    return tokens.flatMap { token in
      expression.matches(in: token.text, range: NSRange(token.text.startIndex..., in: token.text))
        .compactMap { match in
          guard let range = Range(match.range, in: token.text) else { return nil }
          return RegexMatch(value: String(token.text[range]), token: token, range: range)
        }
    }
  }

  fileprivate func applyVocabularyCorrections(
    _ corrections: [PersonalCorrection], to rules: inout EffectiveRules
  ) {
    for correction in corrections {
      switch correction.kind {
      case .customJobTitle:
        rules.jobTitles.insert(correction.match.cardFieldFolded)
      case .phoneLabelInterpretation:
        if let kind = correction.phoneKind {
          rules.phoneLabels[correction.match.cardFieldFolded] = kind
        }
      default:
        break
      }
    }
  }

  fileprivate func applyOrganizationCorrections(
    _ corrections: [PersonalCorrection],
    emailDomain: String?,
    tokens: [WorkingLine],
    result: inout CardFieldResult,
    consumed: inout Set<String>
  ) {
    for correction in corrections {
      if correction.kind == .emailDomainOrganization,
        emailDomain?.cardFieldFolded == correction.match.cardFieldFolded,
        let replacement = correction.replacement,
        let source = result.emailAddresses.first?.sourceTokenIdentifiers
      {
        result.organization = ClassifiedValue(
          normalizedValue: replacement,
          originalValue: replacement,
          confidence: 0.99,
          evidence: [.emailDomainHint, .userCorrection],
          sourceTokenIdentifiers: source
        )
      } else if correction.kind == .organizationAlias, let replacement = correction.replacement,
        let line = tokens.first(where: {
          $0.text.cardFieldFolded == correction.match.cardFieldFolded
        })
      {
        result.organization = value(line, confidence: 0.99, evidence: [.userCorrection])
        result.organization?.normalizedValue = replacement
        consumed.insert(line.token.id)
      }
    }
  }

  fileprivate func applyPreferredNameCorrections(
    _ corrections: [PersonalCorrection], result: inout CardFieldResult
  ) {
    guard let fullName = result.fullName else { return }
    if let correction = corrections.first(where: {
      $0.kind == .preferredNameOrdering
        && $0.match.cardFieldFolded == fullName.normalizedValue.cardFieldFolded
    }), let replacement = correction.replacement {
      result.preferredName = ClassifiedValue(
        normalizedValue: replacement,
        originalValue: fullName.originalValue,
        confidence: 0.99,
        evidence: [.userCorrection],
        sourceTokenIdentifiers: fullName.sourceTokenIdentifiers
      )
    }
  }

  fileprivate func applyReclassificationCorrections(
    _ corrections: [PersonalCorrection],
    tokens: [WorkingLine],
    result: inout CardFieldResult,
    consumed: inout Set<String>
  ) {
    for correction in corrections where correction.kind == .reclassifyPattern {
      guard let target = correction.targetField,
        let line = tokens.first(where: {
          $0.text.cardFieldFolded == correction.match.cardFieldFolded
        })
      else { continue }
      let corrected = value(line, confidence: 0.99, evidence: [.userCorrection])
      switch target {
      case .fullName: result.fullName = corrected
      case .jobTitle: result.jobTitle = corrected
      case .department: result.department = corrected
      case .organization: result.organization = corrected
      case .alternateNames: result.alternateNames.append(corrected)
      case .preferredName: result.preferredName = corrected
      case .emailAddresses: result.emailAddresses.append(corrected)
      case .mobilePhoneNumbers: result.mobilePhoneNumbers.append(corrected)
      case .workPhoneNumbers: result.workPhoneNumbers.append(corrected)
      case .faxNumbers: result.faxNumbers.append(corrected)
      case .websites: result.websites.append(corrected)
      case .professionalProfileURLs: result.professionalProfileURLs.append(corrected)
      case .socialHandles: result.socialHandles.append(corrected)
      case .addresses: result.addresses.append(corrected)
      }
      consumed.insert(line.token.id)
    }
  }

  fileprivate func allValues(in result: CardFieldResult) -> [ClassifiedValue] {
    [
      result.fullName, result.preferredName, result.jobTitle, result.department,
      result.organization,
    ].compactMap { $0 } + result.alternateNames + result.emailAddresses + result.mobilePhoneNumbers
      + result.workPhoneNumbers + result.faxNumbers + result.websites
      + result.professionalProfileURLs + result.socialHandles + result.addresses
  }
}

extension Array where Element == ClassifiedValue {
  fileprivate func uniqued() -> [ClassifiedValue] {
    var seen = Set<String>()
    return filter { seen.insert($0.normalizedValue.cardFieldFolded).inserted }
  }
}
