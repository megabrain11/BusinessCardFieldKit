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
    let webResults = extractWebValues(tokens, rules: rules, consumed: &consumed)
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

    let domainHints = result.emailAddresses.compactMap { value in
      value.normalizedValue.split(separator: "@").last.map(String.init)
    }
    let domainHint = domainHints.first
    let organizationCandidates = organizationCandidates(
      expanded,
      rules: rules,
      emailDomains: domainHints,
      excluding: consumed
    )
    if let firstOrganization = organizationCandidates.first {
      result.organization = withAlternatives(
        firstOrganization, from: Array(organizationCandidates.dropFirst()))
      if let competingOrganization = organizationCandidates.dropFirst().first(where: {
        Set($0.value.sourceTokenIdentifiers).isDisjoint(
          with: firstOrganization.value.sourceTokenIdentifiers)
      }), competingOrganization.value.confidence >= firstOrganization.value.confidence - 0.05 {
        result.warnings.append(.identityConflict)
        result.warnings.append(.reviewRecommended)
      }
    }
    if let organization = result.organization {
      consumed.formUnion(organization.sourceTokenIdentifiers)
    }

    let names = nameCandidates(
      expanded,
      rules: rules,
      emailLocalParts: result.emailAddresses.compactMap {
        $0.normalizedValue.split(separator: "@").first.map(String.init)
      },
      emailDomains: domainHints,
      excluding: consumed
    )
    if let first = names.first, first.value.confidence >= 0.66 {
      result.fullName = withAlternatives(first, from: Array(names.dropFirst()))
      consumed.formUnion(first.value.sourceTokenIdentifiers)
      result.alternateNames = names.dropFirst().filter { candidate in
        candidate.value.confidence >= 0.66
          && candidate.value.sourceTokenIdentifiers != first.value.sourceTokenIdentifiers
          && areLikelyNameVariants(first, candidate)
          && !isUnsupportedSingleLatinName(candidate)
      }.map(\.value)
      for alternateName in result.alternateNames {
        consumed.formUnion(alternateName.sourceTokenIdentifiers)
      }
      if let competingName = names.dropFirst().first(where: {
        !areLikelyNameVariants(first, $0)
      }), competingName.value.confidence >= first.value.confidence - 0.10 {
        result.warnings.append(.ambiguousPersonName)
        result.warnings.append(.identityConflict)
        result.warnings.append(.reviewRecommended)
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

    if let fullName = result.fullName, let organization = result.organization,
      !Set(fullName.sourceTokenIdentifiers).isDisjoint(
        with: organization.sourceTokenIdentifiers)
    {
      result.warnings.append(.identityConflict)
      result.warnings.append(.reviewRecommended)
    }

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
      for separator in ["|", "/", "·", ";", "；", ",", "，"] {
        let parts = token.text.split(separator: Character(separator), maxSplits: 1)
        if parts.count == 2 {
          let lhs = parts[0].trimmingCharacters(in: .whitespaces)
          let rhs = parts[1].trimmingCharacters(in: .whitespaces)
          if isInlineNameSegment(lhs, rules: rules), isJobTitleLike(rhs, rules: rules) {
            return [
              WorkingLine(text: lhs, token: token, position: position),
              WorkingLine(text: rhs, token: token, position: position),
            ]
          }
        }
      }
      if let parts = splitInlineNameAndTitle(token.text, rules: rules) {
        return [
          WorkingLine(text: parts.name, token: token, position: position),
          WorkingLine(text: parts.title, token: token, position: position),
        ]
      }
      let cleanedIdentity = token.text.replacingOccurrences(
        of: #"\s+[\p{P}\p{S}]{2,}\s*$"#,
        with: "",
        options: .regularExpression
      )
      if cleanedIdentity != token.text, isInlineNameSegment(cleanedIdentity, rules: rules) {
        return [WorkingLine(text: cleanedIdentity, token: token, position: position)]
      }
      return [WorkingLine(text: token.text, token: token, position: position)]
    }
  }

  fileprivate func splitInlineNameAndTitle(_ text: String, rules: EffectiveRules)
    -> (name: String, title: String)?
  {
    guard !isPureJobTitle(text, rules: rules) else { return nil }
    let components = text.split(whereSeparator: \.isWhitespace).map(String.init)
    guard components.count >= 2 else { return nil }
    for split in stride(from: components.count - 1, through: 1, by: -1) {
      let lhs = components[..<split].joined(separator: " ")
      let rhs = components[split...].joined(separator: " ")
      let lhsComponents = lhs.split(whereSeparator: \.isWhitespace)
      let titleBeginsWithLatin =
        rhs.unicodeScalars.first.map {
          CharacterSet.letters.contains($0) && !isCJKScalar($0)
        } == true
      let compactCJKName =
        lhsComponents.count == 1 && (2...4).contains(lhs.unicodeScalars.count)
        && lhs.unicodeScalars.allSatisfy(isCJKScalar)
      if lhsComponents.count >= 2 || compactCJKName, titleBeginsWithLatin,
        !isDepartmentLike(lhs, rules: rules),
        isInlineNameSegment(lhs, rules: rules), isJobTitleLike(rhs, rules: rules)
      {
        return (lhs, rhs)
      }
    }
    return nil
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
    var inheritedKinds: [String: PhoneKind] = [:]
    let tokenPositions = Dictionary(
      uniqueKeysWithValues: tokens.enumerated().map { ($0.element.id, $0.offset) })
    for match in matches where match.value.filter(\.isNumber).count >= 7 {
      let prefix = String(match.token.text.prefix(upTo: match.range.lowerBound))
        .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":.-|")))
        .cardFieldFolded
      let inlineKind = matchedPhoneKind(prefix: prefix, rules: rules)
      let adjacentLabel = adjacentPhoneLabel(
        for: match.token,
        tokens: tokens,
        tokenPositions: tokenPositions,
        rules: rules
      )
      guard var kind = inlineKind ?? inheritedKinds[match.token.id] ?? adjacentLabel?.kind else {
        hasAmbiguousNumber = true
        continue
      }
      inheritedKinds[match.token.id] = kind
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
      if let labelToken = adjacentLabel?.token {
        consumed.insert(labelToken.id)
      }
      let trimmed = match.value.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;"))
      let normalized = trimmed.filter { $0.isNumber || $0 == "+" }
      let sourceIdentifiers = [adjacentLabel?.token.id, match.token.id].compactMap { $0 }
      let classified = ClassifiedValue(
        normalizedValue: normalized,
        originalValue: trimmed,
        confidence: 0.68 + match.token.confidence * 0.27,
        evidence: evidence,
        sourceTokenIdentifiers: sourceIdentifiers
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

  fileprivate func adjacentPhoneLabel(
    for token: OCRToken,
    tokens: [OCRToken],
    tokenPositions: [String: Int],
    rules: EffectiveRules
  ) -> (kind: PhoneKind, token: OCRToken)? {
    guard let position = tokenPositions[token.id], position > tokens.startIndex else { return nil }
    let candidate = tokens[tokens.index(before: position)]
    guard let kind = barePhoneLabelKind(candidate.text, rules: rules) else { return nil }

    let sameRowTolerance = max(0.035, max(candidate.boundingBox.height, token.boundingBox.height))
    let isSameRow = abs(candidate.boundingBox.midY - token.boundingBox.midY) <= sameRowTolerance
    let isPreviousRow =
      candidate.boundingBox.midY > token.boundingBox.midY
      && candidate.boundingBox.midY - token.boundingBox.midY <= 0.14
    let horizontallyRelated =
      candidate.boundingBox.x <= token.boundingBox.x + token.boundingBox.width
      && token.boundingBox.x <= candidate.boundingBox.x + candidate.boundingBox.width + 0.20
    guard (isSameRow && horizontallyRelated) || isPreviousRow else { return nil }
    return (kind, candidate)
  }

  fileprivate func barePhoneLabelKind(_ text: String, rules: EffectiveRules) -> PhoneKind? {
    let folded = text.cardFieldFolded.trimmingCharacters(
      in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return rules.phoneLabels[folded]
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
    rules: EffectiveRules,
    consumed: inout Set<String>
  ) -> (websites: [ClassifiedValue], profiles: [ClassifiedValue], handles: [ClassifiedValue]) {
    let domains = regexValues(
      #"\b(?:https?://|www\.)?(?:[A-Z0-9\-]+\.)+[A-Z]{2,}(?:/[^\s]*)?\b"#,
      tokens: tokens,
      options: [.caseInsensitive]
    ).filter {
      !isEmbeddedInEmail($0) && !isLegalEntityNotation($0, rules: rules)
        && !isJobTitleDomainNotation($0.value, rules: rules)
    }
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

  fileprivate func isLegalEntityNotation(_ match: RegexMatch, rules: EffectiveRules) -> Bool {
    let trimmedToken = match.token.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedToken.cardFieldFolded == match.value.cardFieldFolded,
      !trimmedToken.cardFieldFolded.hasPrefix("www."),
      !trimmedToken.cardFieldFolded.hasPrefix("http://"),
      !trimmedToken.cardFieldFolded.hasPrefix("https://"),
      let separator = trimmedToken.lastIndex(of: ".")
    else { return false }

    let suffix = String(trimmedToken[trimmedToken.index(after: separator)...])
    let foldedSuffix = suffix.cardFieldFolded.trimmingCharacters(in: .punctuationCharacters)
    let hasLegalSuffix = rules.organizationSuffixes.contains {
      $0.trimmingCharacters(in: .punctuationCharacters) == foldedSuffix
    }
    guard hasLegalSuffix else { return false }

    // A capitalized legal suffix (for example, `Brand.Inc`) is common OCR output
    // for a printed entity name. Explicit URL prefixes still take precedence.
    return suffix.unicodeScalars.first.map(CharacterSet.uppercaseLetters.contains) == true
      || suffix == suffix.uppercased()
  }

  fileprivate func isEmbeddedInEmail(_ match: RegexMatch) -> Bool {
    let text = match.token.text
    let lowerBound =
      text[..<match.range.lowerBound].lastIndex(where: \Character.isWhitespace)
      .map { text.index(after: $0) } ?? text.startIndex
    let upperBound =
      text[match.range.upperBound...].firstIndex(where: \Character.isWhitespace)
      ?? text.endIndex
    return text[lowerBound..<upperBound].contains("@")
  }

  fileprivate func isJobTitleDomainNotation(_ value: String, rules: EffectiveRules) -> Bool {
    let labels = value.split(separator: ".").map {
      String($0).cardFieldFolded.trimmingCharacters(in: .punctuationCharacters)
    }
    return labels.count >= 2 && labels.allSatisfy(rules.jobTitles.contains)
  }

  fileprivate func bestJobTitle(
    _ lines: [WorkingLine],
    rules: EffectiveRules,
    excluding: Set<String>
  ) -> ClassifiedValue? {
    lines.filter { !excluding.contains($0.token.id) && isJobTitleLike($0.text, rules: rules) }
      .filter { line in
        !isOrganizationLike(line.text, rules: rules)
          || startsWithJobTitle(line.text, rules: rules)
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

  fileprivate func startsWithJobTitle(_ text: String, rules: EffectiveRules) -> Bool {
    let folded = text.cardFieldFolded.trimmingCharacters(in: .whitespacesAndNewlines)
    return rules.jobTitles.sorted(by: { $0.count > $1.count }).contains { title in
      guard folded.hasPrefix(title) else { return false }
      guard folded.count > title.count else { return true }
      let boundary = folded.index(folded.startIndex, offsetBy: title.count)
      return !folded[boundary].isLetter && !folded[boundary].isNumber
        || folded[boundary].isWhitespace
    }
  }

  fileprivate func bestDepartment(
    _ lines: [WorkingLine],
    rules: EffectiveRules,
    excluding: Set<String>
  ) -> ClassifiedValue? {
    lines.filter {
      !excluding.contains($0.token.id) && isDepartmentLike($0.text, rules: rules)
        && !isJobTitleLike($0.text, rules: rules)
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
    var seenTokens = Set<String>()
    let uniqueLines = lines.filter { seenTokens.insert($0.token.id).inserted }
    var usedTokens = Set<String>()
    var addresses: [ClassifiedValue] = []

    for (index, line) in uniqueLines.enumerated() {
      guard !excluding.contains(line.token.id), !usedTokens.contains(line.token.id),
        isAddressLike(line.text, rules: rules)
      else { continue }

      var group = [line]
      var previous = line
      for candidate in uniqueLines.dropFirst(index + 1).prefix(3) {
        guard !excluding.contains(candidate.token.id), !usedTokens.contains(candidate.token.id),
          candidate.position <= previous.position + 1,
          areAddressLinesNearby(previous, candidate)
        else { break }

        if isAddressLike(candidate.text, rules: rules) {
          // Fully self-contained address lines are separate values unless the
          // previous OCR line visibly continues with punctuation.
          guard previous.text.trimmingCharacters(in: .whitespaces).hasSuffix(",") else { break }
        } else {
          guard
            isAddressContinuation(
              candidate.text,
              previousText: previous.text,
              rules: rules
            )
          else { break }
        }
        group.append(candidate)
        previous = candidate
      }

      let sourceIdentifiers = group.map(\.token.id)
      usedTokens.formUnion(sourceIdentifiers)
      let normalized = group.map(\.text).joined(separator: " ")
      let meanConfidence = group.map(\.token.confidence).reduce(0, +) / Double(group.count)
      let evidence =
        [.addressVocabulary]
        + group.flatMap { packEvidence(for: $0.text, rules: rules) }
      addresses.append(
        ClassifiedValue(
          normalizedValue: normalized,
          originalValue: normalized,
          confidence: 0.56 + meanConfidence * 0.28,
          evidence: evidence,
          sourceTokenIdentifiers: sourceIdentifiers
        ))
    }
    return addresses.uniqued()
  }

  fileprivate func areAddressLinesNearby(_ lhs: WorkingLine, _ rhs: WorkingLine) -> Bool {
    let verticalGap =
      lhs.token.boundingBox.y - (rhs.token.boundingBox.y + rhs.token.boundingBox.height)
    let aligned = abs(lhs.token.boundingBox.x - rhs.token.boundingBox.x) <= 0.24
    return verticalGap <= 0.12 && aligned
  }

  fileprivate func isAddressContinuation(
    _ text: String,
    previousText: String,
    rules: EffectiveRules
  ) -> Bool {
    guard !isContactLabelLike(text, rules: rules), !isJobTitleLike(text, rules: rules),
      text.range(
        of: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+"#, options: [.regularExpression, .caseInsensitive])
        == nil
    else { return false }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let postalOnly =
      trimmed.range(
        of: #"^[A-Z0-9][A-Z0-9 \-]{2,9}$"#,
        options: [.regularExpression, .caseInsensitive]
      ) != nil && trimmed.contains(where: \.isNumber)
    let hasAddressTerm = rules.contains(rules.addressTerms, in: trimmed)
    let countryOrLocalityTerms = [
      "korea", "singapore", "philippines", "india", "netherlands", "canada", "united states",
      "republic of", "bengaluru", "manila", "amsterdam", "seoul", "서울", "대한민국",
    ]
    let isLocality = countryOrLocalityTerms.contains { trimmed.cardFieldFolded.contains($0) }
    let continuesPunctuation =
      previousText.trimmingCharacters(in: .whitespaces).hasSuffix(",")
      && trimmed.split(separator: " ").count <= 12
    return postalOnly || hasAddressTerm || isLocality || continuesPunctuation
  }

  fileprivate func organizationCandidates(
    _ lines: [WorkingLine],
    rules: EffectiveRules,
    emailDomains: [String],
    excluding: Set<String>
  ) -> [InternalCandidate] {
    let domainRoots = emailDomains.compactMap {
      $0.split(separator: ".").first.map(String.init)?.cardFieldIdentityKey
    }.filter { !$0.isEmpty }
    var seenTokens = Set<String>()
    let uniqueLines = lines.filter { seenTokens.insert($0.token.id).inserted }
    var candidates: [InternalCandidate] = []

    for line in uniqueLines {
      guard !excluding.contains(line.token.id),
        !isLikelyUppercasePersonLine(line, among: lines, rules: rules),
        isOrganizationLike(line.text, rules: rules)
          || matchesOrganizationDomain(line.text, roots: domainRoots)
      else { continue }
      candidates.append(
        organizationCandidate(
          from: [line], rules: rules, domainRoots: domainRoots, compoundBonus: 0))
    }

    guard uniqueLines.count >= 2 else { return candidates.sorted(by: candidateOrder) }
    for firstIndex in uniqueLines.indices {
      let secondLimit = min(uniqueLines.count, firstIndex + 4)
      guard firstIndex + 1 < secondLimit else { continue }
      for secondIndex in (firstIndex + 1)..<secondLimit {
        let pair = [uniqueLines[firstIndex], uniqueLines[secondIndex]]
        appendOrganizationCompound(
          pair,
          to: &candidates,
          among: lines,
          rules: rules,
          domainRoots: domainRoots,
          excluding: excluding
        )

        let thirdLimit = min(uniqueLines.count, secondIndex + 4)
        guard secondIndex + 1 < thirdLimit else { continue }
        for thirdIndex in (secondIndex + 1)..<thirdLimit {
          appendOrganizationCompound(
            [uniqueLines[firstIndex], uniqueLines[secondIndex], uniqueLines[thirdIndex]],
            to: &candidates,
            among: lines,
            rules: rules,
            domainRoots: domainRoots,
            excluding: excluding
          )
        }
      }
    }

    var seenValues = Set<String>()
    return candidates.sorted(by: candidateOrder).filter {
      seenValues.insert($0.value.normalizedValue.cardFieldIdentityKey).inserted
    }
  }

  fileprivate func appendOrganizationCompound(
    _ group: [WorkingLine],
    to candidates: inout [InternalCandidate],
    among allLines: [WorkingLine],
    rules: EffectiveRules,
    domainRoots: [String],
    excluding: Set<String>
  ) {
    guard group.allSatisfy({ !excluding.contains($0.token.id) }),
      group.allSatisfy({ !isLikelyUppercasePersonLine($0, among: allLines, rules: rules) }),
      zip(group, group.dropFirst()).allSatisfy({ areLogoLinesNearby($0, $1) }),
      group.allSatisfy({ isOrganizationFragment($0.text, rules: rules) })
    else { return }

    let combined = group.map(\.text).joined(separator: " ")
    guard
      isOrganizationLike(combined, rules: rules)
        || matchesOrganizationDomain(combined, roots: domainRoots)
    else { return }
    candidates.append(
      organizationCandidate(
        from: group,
        rules: rules,
        domainRoots: domainRoots,
        compoundBonus: Double(group.count - 1) * 0.05
      ))
  }

  fileprivate func organizationCandidate(
    from lines: [WorkingLine],
    rules: EffectiveRules,
    domainRoots: [String],
    compoundBonus: Double
  ) -> InternalCandidate {
    let text = lines.map(\.text).joined(separator: " ")
    let meanConfidence = lines.map(\.token.confidence).reduce(0, +) / Double(lines.count)
    var score = 0.49 + meanConfidence * 0.24 + compoundBonus
    var evidence: [Evidence] = []
    if rules.contains(rules.organizationSuffixes, in: text) {
      score += 0.16
      evidence.append(.organizationSuffix)
    }
    if rules.contains(rules.organizationTerms, in: text) || isUppercaseBrand(text) {
      score += 0.13
      evidence.append(.organizationVocabulary)
    }
    if matchesOrganizationDomain(text, roots: domainRoots) {
      score += 0.14
      evidence.append(.emailDomainHint)
    }
    if lines.contains(where: { $0.token.boundingBox.height >= 0.07 }) {
      score += 0.06
      evidence.append(.layoutProminence)
    }
    evidence.append(contentsOf: lines.flatMap { packEvidence(for: $0.text, rules: rules) })
    let value = ClassifiedValue(
      normalizedValue: text,
      originalValue: text,
      confidence: min(score, 0.98),
      evidence: evidence,
      sourceTokenIdentifiers: lines.map(\.token.id)
    )
    return InternalCandidate(value: value, position: lines.first?.position ?? 0)
  }

  fileprivate func matchesOrganizationDomain(_ text: String, roots: [String]) -> Bool {
    let key = text.cardFieldIdentityKey
    return roots.contains { root in key == root || (key.count >= 5 && key.contains(root)) }
  }

  fileprivate func isOrganizationFragment(_ text: String, rules: EffectiveRules) -> Bool {
    guard !isContactLabelLike(text, rules: rules), !isJobTitleLike(text, rules: rules),
      !isAddressLike(text, rules: rules), !isSloganLike(text, rules: rules),
      text.range(of: #"[@:]"#, options: .regularExpression) == nil,
      (1...5).contains(text.split(whereSeparator: \.isWhitespace).count)
    else { return false }
    let letters = text.filter(\.isLetter)
    guard letters.count >= 2 else { return false }
    return isOrganizationLike(text, rules: rules) || isUppercaseBrand(text)
      || (containsLatin(text) && String(letters) == String(letters).lowercased())
      || (containsLatin(text)
        && text.range(of: #"^[A-Z][A-Za-z0-9]*$"#, options: .regularExpression) != nil)
  }

  fileprivate func areLogoLinesNearby(_ lhs: WorkingLine, _ rhs: WorkingLine) -> Bool {
    guard rhs.position <= lhs.position + 3 else { return false }
    let sameRow = abs(lhs.token.boundingBox.midY - rhs.token.boundingBox.midY) <= 0.05
    let horizontalGap = max(
      rhs.token.boundingBox.x - (lhs.token.boundingBox.x + lhs.token.boundingBox.width),
      lhs.token.boundingBox.x - (rhs.token.boundingBox.x + rhs.token.boundingBox.width)
    )
    let verticallyStacked =
      abs(lhs.token.boundingBox.x - rhs.token.boundingBox.x) <= 0.20
      && abs(lhs.token.boundingBox.midY - rhs.token.boundingBox.midY) <= 0.15
    return (sameRow && horizontalGap <= 0.16) || verticallyStacked
  }

  fileprivate func nameCandidates(
    _ lines: [WorkingLine],
    rules: EffectiveRules,
    emailLocalParts: [String],
    emailDomains: [String],
    excluding: Set<String>
  ) -> [InternalCandidate] {
    let domainRoots = emailDomains.compactMap {
      $0.split(separator: ".").first.map(String.init)?.cardFieldIdentityKey
    }.filter { !$0.isEmpty }
    var candidates = lines.compactMap { line -> InternalCandidate? in
      // A name and role may share one source observation, so a consumed token can
      // still contribute a distinct, conservatively validated identity segment.
      let sharesInlineTitle = lines.contains {
        $0.token.id == line.token.id && $0.text != line.text
          && isJobTitleLike($0.text, rules: rules)
      }
      let emailMatch = emailLocalParts.contains { emailMatchesName($0, name: line.text) }
      guard !excluding.contains(line.token.id) || sharesInlineTitle,
        emailMatch || !matchesOrganizationDomain(line.text, roots: domainRoots),
        isNameLike(line.text, rules: rules)
          || isLikelyUppercasePersonLine(line, among: lines, rules: rules)
      else { return nil }
      var score = 0.43 + line.token.confidence * 0.20
      var evidence: [Evidence] = []
      if line.position == 0 { score += 0.08 }
      if line.token.boundingBox.height >= 0.055 {
        score += 0.10
        evidence.append(.layoutProminence)
      }
      if emailMatch {
        score += 0.17
        evidence.append(.matchesEmailLocalPart)
      }
      if lines.contains(where: {
        abs($0.position - line.position) <= 2
          && $0.token.id != line.token.id && isJobTitleLike($0.text, rules: rules)
      }) {
        score += 0.10
        evidence.append(.nearJobTitle)
      }
      if containsCJK(line.text) && containsLatin(line.text)
        || lines.contains(where: {
          abs($0.position - line.position) <= 2 && $0.token.id != line.token.id
            && containsCJK($0.text) != containsCJK(line.text)
            && (containsLatin($0.text) || containsLatin(line.text))
        })
      {
        score += 0.06
        evidence.append(.multilingualVariant)
      }
      if containsCJK(line.text) && !containsLatin(line.text) {
        score += 0.08
      }
      let isSingleLatinToken =
        line.text.split(whereSeparator: \.isWhitespace).count == 1 && containsLatin(line.text)
        && !containsCJK(line.text)
      if isSingleLatinToken && !emailMatch {
        score -= 0.18
      }
      return InternalCandidate(
        value: value(line, confidence: min(score, 0.96), evidence: evidence),
        position: line.position)
    }

    var seenTokens = Set<String>()
    let uniqueLines = lines.filter { seenTokens.insert($0.token.id).inserted }
    if uniqueLines.count >= 2 {
      for firstIndex in 0..<(uniqueLines.count - 1) {
        let secondLimit = min(uniqueLines.count, firstIndex + 4)
        for secondIndex in (firstIndex + 1)..<secondLimit {
          let pair = [uniqueLines[firstIndex], uniqueLines[secondIndex]]
          let combined = pair.map(\.text).joined(separator: " ")
          let sameScript = containsCJK(pair[0].text) == containsCJK(pair[1].text)
          let emailMatch = emailLocalParts.contains { emailMatchesName($0, name: combined) }
          let allUppercase = pair.allSatisfy {
            isUppercasePersonForm($0.text, rules: rules)
          }
          guard sameScript, emailMatch || allUppercase,
            pair.allSatisfy({ !excluding.contains($0.token.id) }),
            pair.allSatisfy({
              !isDepartmentLike($0.text, rules: rules)
                && !isJobTitleLike($0.text, rules: rules)
            }),
            zip(pair, pair.dropFirst()).allSatisfy({ areLogoLinesNearby($0, $1) }),
            isInlineNameSegment(combined, rules: rules),
            !isDepartmentLike(combined, rules: rules),
            !matchesOrganizationDomain(combined, roots: domainRoots)
          else { continue }

          let meanConfidence = pair.map(\.token.confidence).reduce(0, +) / Double(pair.count)
          candidates.append(
            InternalCandidate(
              value: ClassifiedValue(
                normalizedValue: combined,
                originalValue: combined,
                confidence: min(0.82 + meanConfidence * 0.15, 0.96),
                evidence: emailMatch
                  ? [.matchesEmailLocalPart, .layoutProminence] : [.layoutProminence],
                sourceTokenIdentifiers: pair.map(\.token.id)
              ),
              position: pair[0].position
            ))
        }
      }
    }

    var seenValues = Set<String>()
    return candidates.sorted(by: candidateOrder).filter {
      seenValues.insert($0.value.normalizedValue.cardFieldIdentityKey).inserted
    }
  }

  fileprivate func isNameLike(_ text: String, rules: EffectiveRules) -> Bool {
    let components = text.split(whereSeparator: \Character.isWhitespace).map(String.init)
    guard (1...7).contains(components.count), text.count <= 90 else { return false }
    let commaSeparatedLatinName =
      text.range(
        of:
          #"^[A-Z][A-Za-z'\-]{1,30},\s*[A-Z][A-Za-z'\-]{1,30}(?:\s+[A-Z][A-Za-z'\-]{1,30}){0,3}$"#,
        options: .regularExpression
      ) != nil
    guard
      commaSeparatedLatinName
        || text.range(of: #"[0-9@:/,.]"#, options: .regularExpression) == nil
    else { return false }
    guard !isContactLabelLike(text, rules: rules), !isJobTitleLike(text, rules: rules),
      !isOrganizationLike(text, rules: rules),
      !isDepartmentLike(text, rules: rules), !isAddressLike(text, rules: rules),
      !isSloganLike(text, rules: rules)
    else { return false }

    if commaSeparatedLatinName { return true }

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
        || $0.range(of: #"^[A-Z][A-Z\-']+$"#, options: .regularExpression) != nil
        || $0.unicodeScalars.allSatisfy(isCJKScalar)
    }
  }

  fileprivate func isInlineNameSegment(_ text: String, rules: EffectiveRules) -> Bool {
    isNameLike(text, rules: rules) || isUppercasePersonForm(text, rules: rules)
  }

  fileprivate func isUppercasePersonForm(_ text: String, rules: EffectiveRules) -> Bool {
    let components = text.split(whereSeparator: \.isWhitespace).map(String.init)
    guard (2...7).contains(components.count), containsLatin(text),
      !containsCJK(text), !isContactLabelLike(text, rules: rules),
      !isJobTitleLike(text, rules: rules), !isAddressLike(text, rules: rules),
      !isSloganLike(text, rules: rules),
      !rules.contains(rules.organizationSuffixes, in: text),
      !rules.contains(rules.organizationTerms, in: text)
    else { return false }
    return components.allSatisfy {
      $0.range(of: #"^[A-Z][A-Z\-']+$"#, options: .regularExpression) != nil
    }
  }

  fileprivate func isLikelyUppercasePersonLine(
    _ line: WorkingLine,
    among lines: [WorkingLine],
    rules: EffectiveRules
  ) -> Bool {
    guard isUppercasePersonForm(line.text, rules: rules) else { return false }
    return lines.contains {
      abs($0.position - line.position) <= 3 && $0.token.id != line.token.id
        && isJobTitleLike($0.text, rules: rules)
    }
  }

  fileprivate func areLikelyNameVariants(
    _ lhs: InternalCandidate,
    _ rhs: InternalCandidate
  ) -> Bool {
    let lhsText = lhs.value.normalizedValue
    let rhsText = rhs.value.normalizedValue
    let differentScripts =
      containsCJK(lhsText) != containsCJK(rhsText)
      && (containsLatin(lhsText) || containsLatin(rhsText))
    let oneContainsOther =
      lhsText.cardFieldIdentityKey.contains(rhsText.cardFieldIdentityKey)
      || rhsText.cardFieldIdentityKey.contains(lhsText.cardFieldIdentityKey)
    return abs(lhs.position - rhs.position) <= 3 && (differentScripts || oneContainsOther)
  }

  fileprivate func isUnsupportedSingleLatinName(_ candidate: InternalCandidate) -> Bool {
    let text = candidate.value.normalizedValue
    return text.split(whereSeparator: \.isWhitespace).count == 1 && containsLatin(text)
      && !containsCJK(text) && !candidate.value.evidence.contains(.matchesEmailLocalPart)
  }

  fileprivate func isJobTitleLike(_ text: String, rules: EffectiveRules) -> Bool {
    rules.contains(rules.jobTitles, in: text)
  }

  fileprivate func isOrganizationLike(_ text: String, rules: EffectiveRules) -> Bool {
    guard !isContactLabelLike(text, rules: rules), !isPureJobTitle(text, rules: rules),
      !isDepartmentLike(text, rules: rules), !isSloganLike(text, rules: rules)
    else { return false }
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

  fileprivate func isPureJobTitle(_ text: String, rules: EffectiveRules) -> Bool {
    let folded = text.cardFieldFolded.trimmingCharacters(
      in: .whitespacesAndNewlines.union(.punctuationCharacters))
    if rules.jobTitles.contains(folded) { return true }
    var remainder = folded
    for title in rules.jobTitles.sorted(by: { $0.count > $1.count }) {
      remainder = remainder.replacingOccurrences(of: title, with: " ")
    }
    let connectors = ["&", "/", "·", "and", "및"]
    for connector in connectors {
      remainder = remainder.replacingOccurrences(of: connector, with: " ")
    }
    return remainder.split(whereSeparator: \.isWhitespace).isEmpty
  }

  fileprivate func isDepartmentLike(_ text: String, rules: EffectiveRules) -> Bool {
    let folded = text.cardFieldFolded
    guard rules.contains(rules.departmentTerms, in: folded) else { return false }
    let unitTerms = [
      "team", "department", "division", "group", "unit", "office", "analytics", "본부", "센터",
      "과", "팀", "부서", "부문", "실",
    ]
    if unitTerms.contains(where: { folded == $0 || folded.contains($0) }) { return true }
    return rules.departmentTerms.contains(folded)
  }

  fileprivate func isContactLabelLike(_ text: String, rules: EffectiveRules) -> Bool {
    let folded = text.cardFieldFolded.trimmingCharacters(
      in: .whitespacesAndNewlines.union(.punctuationCharacters))
    if rules.phoneLabels[folded] != nil { return true }
    let labels: Set<String> = [
      "mobile", "cell", "phone", "telephone", "tel", "office", "direct", "fax",
      "email", "e-mail", "mail", "web", "website", "url", "address", "registered address",
      "reg address", "모바일", "휴대", "휴대폰", "핸드폰", "전화", "팩스", "이메일", "메일", "웹",
      "홈페이지", "주소",
    ]
    return labels.contains(folded)
  }

  fileprivate func isAddressLike(_ text: String, rules: EffectiveRules) -> Bool {
    let digitCount = text.filter(\.isNumber).count
    let hasAddressTerm = rules.contains(rules.addressTerms, in: text)
    let postalPattern =
      text.range(of: #"\b\d{3,6}(?:-\d{3,4})?\b"#, options: .regularExpression) != nil
    let romanizedKoreanStreet =
      text.range(
        of: #"\b\d+(?:-\d+)?,\s*[A-Z][A-Za-z'\-]*-(?:ro|gil)\b"#,
        options: [.regularExpression, .caseInsensitive]
      ) != nil
    return (hasAddressTerm && (digitCount > 0 || postalPattern)) || romanizedKoreanStreet
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
    let uppercaseCount = trimmed.unicodeScalars.filter(CharacterSet.uppercaseLetters.contains).count
    if trimmed.count <= 6, uppercaseCount >= 3 { return false }
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
    if nameParts.filter({ localKey.contains($0) }).count >= 2 { return true }
    guard nameParts.count >= 2, let surname = nameParts.last else { return false }
    let initialsAndSurname =
      nameParts.dropLast().compactMap(\.first).map(String.init).joined()
      + surname
    return localKey == initialsAndSurname || localKey.hasPrefix(initialsAndSurname)
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
    if lhs.value.sourceTokenIdentifiers.count != rhs.value.sourceTokenIdentifiers.count {
      return lhs.value.sourceTokenIdentifiers.count > rhs.value.sourceTokenIdentifiers.count
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
