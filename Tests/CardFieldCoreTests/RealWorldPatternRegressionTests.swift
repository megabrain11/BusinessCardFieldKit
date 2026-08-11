import CardFieldCore
import Testing

private func patternToken(
  _ text: String,
  id: String,
  x: Double = 0.1,
  y: Double,
  width: Double = 0.72,
  height: Double = 0.05,
  confidence: Double = 0.96,
  language: String? = nil
) -> OCRToken {
  OCRToken(
    id: id,
    text: text,
    boundingBox: .init(x: x, y: y, width: width, height: height),
    confidence: confidence,
    language: language
  )
}

@Test("Contact label words never become people or organizations")
func contactLabelsAreNotIdentities() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Mobile", id: "mobile", y: 0.82, height: 0.09),
    patternToken("E-mail", id: "email", y: 0.70, height: 0.08),
    patternToken("Web", id: "web", y: 0.58, height: 0.08),
    patternToken("Address", id: "address", y: 0.46, height: 0.08),
    patternToken("CEO", id: "title", y: 0.34),
  ])

  #expect(result.fullName == nil)
  #expect(result.organization == nil)
  #expect(result.jobTitle?.normalizedValue == "CEO")
}

@Test("Semicolon-separated inline names and titles are classified independently")
func semicolonSeparatedNameAndTitle() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Casey Rowan ; CEO", id: "identity", y: 0.78, height: 0.09),
    patternToken("EXAMPLE WORKS", id: "organization", y: 0.58, height: 0.08),
  ])

  #expect(result.fullName?.normalizedValue == "Casey Rowan")
  #expect(result.jobTitle?.normalizedValue == "CEO")
  #expect(result.organization?.normalizedValue == "EXAMPLE WORKS")
  #expect(result.fullName?.sourceTokenIdentifiers == ["identity"])
}

@Test("Adjacent logo lines form one organization instead of competing fragments")
func multilineOrganizationLogo() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("THE", id: "org-1", x: 0.10, y: 0.84, width: 0.30, height: 0.075),
    patternToken("EXAMPLE", id: "org-2", x: 0.10, y: 0.76, width: 0.36, height: 0.075),
    patternToken("GROUP", id: "org-3", x: 0.10, y: 0.68, width: 0.32, height: 0.075),
    patternToken("hello@example.example", id: "email", y: 0.22),
  ])

  #expect(result.organization?.normalizedValue == "THE EXAMPLE GROUP")
  #expect(result.organization?.sourceTokenIdentifiers == ["org-1", "org-2", "org-3"])
}

@Test("A split lowercase logo can be joined using the email-domain hint")
func splitLogoUsesDomainHint() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("open", id: "org-1", x: 0.10, y: 0.82, width: 0.22, height: 0.08),
    patternToken("harbor", id: "org-2", x: 0.10, y: 0.73, width: 0.27, height: 0.08),
    patternToken("Avery Quinn", id: "name", x: 0.52, y: 0.82, width: 0.32, height: 0.08),
    patternToken("Founder", id: "title", x: 0.52, y: 0.72, width: 0.25),
    patternToken("avery@openharbor.example", id: "email", y: 0.20),
  ])

  #expect(result.organization?.normalizedValue == "open harbor")
  #expect(result.fullName?.normalizedValue == "Avery Quinn")
}

@Test("Bilingual names remain person variants even when the Latin variant is uppercase")
func bilingualUppercaseAlternateName() throws {
  let result = try CardFieldClassifier().classify([
    patternToken(
      "김가온", id: "name-ko", x: 0.38, y: 0.82, width: 0.22, height: 0.085, language: "ko"),
    patternToken("GAON KIM", id: "name-en", x: 0.38, y: 0.72, width: 0.28, height: 0.075),
    patternToken("Principal", id: "title", x: 0.68, y: 0.82, width: 0.22),
    patternToken("SAMPLE VENTURES", id: "organization", x: 0.08, y: 0.82, width: 0.24),
    patternToken("gaon.kim@sample.example", id: "email", y: 0.20),
  ])

  let names =
    [result.fullName?.normalizedValue].compactMap { $0 }
    + result.alternateNames.map(\.normalizedValue)
  #expect(names.contains("김가온"))
  #expect(names.contains("GAON KIM"))
  #expect(result.organization?.normalizedValue == "SAMPLE VENTURES")
}

@Test("Functional groups are departments and do not replace a visible organization")
func functionalGroupIsDepartment() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Taylor Morgan", id: "name", y: 0.84, height: 0.08),
    patternToken("Principal", id: "title", y: 0.74),
    patternToken("Investment Group", id: "department", y: 0.64),
    patternToken("SAMPLE VENTURES", id: "organization", y: 0.52, height: 0.08),
  ])

  #expect(result.department?.normalizedValue == "Investment Group")
  #expect(result.organization?.normalizedValue == "SAMPLE VENTURES")
}

@Test("A legal entity suffix is not mistaken for an Internet top-level domain")
func legalSuffixIsNotWebsite() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("ExampleWorks.Inc", id: "organization", y: 0.80, height: 0.09),
    patternToken("Jordan Lee", id: "name", y: 0.66, height: 0.08),
    patternToken("CEO", id: "title", y: 0.56),
  ])

  #expect(result.websites.isEmpty)
  #expect(result.organization?.normalizedValue == "ExampleWorks.Inc")
  #expect(result.fullName?.normalizedValue == "Jordan Lee")
}

@Test("Wrapped address lines are retained as one sourced value")
func wrappedAddressLines() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Registered Address: 741 Example House", id: "address-1", y: 0.48),
    patternToken("Fiction Road, Sample City", id: "address-2", y: 0.40),
    patternToken("560103", id: "address-3", y: 0.32),
  ])

  #expect(
    result.addresses.map(\.normalizedValue) == [
      "Registered Address: 741 Example House Fiction Road, Sample City 560103"
    ])
  #expect(
    result.addresses.first?.sourceTokenIdentifiers == ["address-1", "address-2", "address-3"])
}

@Test("Close competing identity candidates require explicit review")
func ambiguousIdentityRequiresReview() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Morgan Avery", id: "name-1", y: 0.84, height: 0.08),
    patternToken("Avery Morgan", id: "name-2", y: 0.75, height: 0.08),
    patternToken("Chief Executive Officer", id: "title", y: 0.66),
    patternToken("EXAMPLE LABS", id: "organization", y: 0.52, height: 0.08),
  ])

  #expect(result.warnings.contains(.ambiguousPersonName))
  #expect(result.warnings.contains(.identityConflict))
  #expect(result.warnings.contains(.reviewRecommended))
}

@Test("Unlabeled phone numbers remain unresolved after identity improvements")
func patternUnlabeledPhoneRemainsUnresolved() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("+1 202 555 0198", id: "phone", y: 0.22)
  ])

  #expect(result.mobilePhoneNumbers.isEmpty)
  #expect(result.workPhoneNumbers.isEmpty)
  #expect(result.faxNumbers.isEmpty)
  #expect(result.unclassifiedLines.map(\.id) == ["phone"])
  #expect(result.warnings.contains(.ambiguousPhoneNumber))
}

@Test("A nearby standalone phone label types only the adjacent number")
func standalonePhoneLabelTypesAdjacentNumber() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("모바일", id: "label", x: 0.10, y: 0.42, width: 0.15, language: "ko"),
    patternToken("+82 10-5550-1200", id: "phone", x: 0.28, y: 0.42, width: 0.35),
  ])

  #expect(result.mobilePhoneNumbers.map(\.normalizedValue) == ["+821055501200"])
  #expect(result.mobilePhoneNumbers.first?.sourceTokenIdentifiers == ["label", "phone"])
  #expect(!result.warnings.contains(.ambiguousPhoneNumber))
}

@Test("One phone label can govern multiple numbers on the same OCR line")
func sharedInlinePhoneLabelTypesMultipleNumbers() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Mobile +1 202 555 0101 / +1 202 555 0102", id: "phones", y: 0.30)
  ])

  #expect(
    result.mobilePhoneNumbers.map(\.normalizedValue) == ["+12025550101", "+12025550102"])
  #expect(result.workPhoneNumbers.isEmpty)
  #expect(!result.warnings.contains(.ambiguousPhoneNumber))
}

@Test("Spaced Korean names remain names and can share a line with a Latin title")
func spacedKoreanNameWithInlineTitle() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("예 시 인 CEO", id: "identity", y: 0.80, height: 0.09, language: "ko"),
    patternToken("SAMPLE STUDIO", id: "organization", y: 0.60, height: 0.08),
  ])

  #expect(result.fullName?.normalizedValue == "예 시 인")
  #expect(result.jobTitle?.normalizedValue == "CEO")
  #expect(result.organization?.normalizedValue == "SAMPLE STUDIO")
}

@Test("Slash-delimited functional units remain a department rather than an organization")
func slashDelimitedDepartment() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Avery Rowan", id: "name", y: 0.82, height: 0.08),
    patternToken("Principal", id: "title", y: 0.72),
    patternToken("Investment Group / Investment Team", id: "department", y: 0.62),
    patternToken("SAMPLE CAPITAL", id: "organization", y: 0.50, height: 0.08),
  ])

  #expect(result.department?.normalizedValue == "Investment Group / Investment Team")
  #expect(result.organization?.normalizedValue == "SAMPLE CAPITAL")
}

@Test("All-caps multipart person lines join when supported by title and email evidence")
func uppercaseMultipartPersonName() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("AVERY NATHANIEL", id: "name-1", x: 0.10, y: 0.84, width: 0.40, height: 0.08),
    patternToken("QUILL MERIDIAN WREN", id: "name-2", x: 0.10, y: 0.75, width: 0.42, height: 0.08),
    patternToken("Group Chairman & CEO", id: "title", x: 0.10, y: 0.65, width: 0.36),
    patternToken(
      "WORLD SAMPLE CHAIN", id: "organization", x: 0.58, y: 0.82, width: 0.32, height: 0.08),
    patternToken("avery@worldsample.example", id: "email", y: 0.20),
  ])

  #expect(result.fullName?.normalizedValue == "AVERY NATHANIEL QUILL MERIDIAN WREN")
  #expect(result.fullName?.sourceTokenIdentifiers == ["name-1", "name-2"])
  #expect(result.jobTitle?.normalizedValue == "Group Chairman & CEO")
}

@Test("A long multipart name can span two adjacent OCR lines")
func longNameAcrossOCRLines() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Elara", id: "name-1", x: 0.20, y: 0.84, width: 0.28, height: 0.08),
    patternToken("de Vale de Solano", id: "name-2", x: 0.20, y: 0.75, width: 0.42, height: 0.08),
    patternToken("elara@samplechain.example", id: "email", y: 0.25),
    patternToken("SAMPLE CHAIN", id: "organization", y: 0.55, height: 0.08),
  ])

  #expect(result.fullName?.normalizedValue == "Elara de Vale de Solano")
  #expect(result.fullName?.sourceTokenIdentifiers == ["name-1", "name-2"])
}

@Test("A complete multiword title is never split into a person and a title fragment")
func completeTitleIsNotSplit() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Chief Executive Officer", id: "title", y: 0.78, height: 0.08),
    patternToken("EXAMPLE HOLDINGS", id: "organization", y: 0.60, height: 0.08),
  ])

  #expect(result.fullName == nil)
  #expect(result.jobTitle?.normalizedValue == "Chief Executive Officer")
  #expect(result.organization?.normalizedValue == "EXAMPLE HOLDINGS")
}

@Test("Comma and compact CJK layouts split a visible name from its title")
func commaAndCompactCJKNameTitleLayouts() throws {
  let commaResult = try CardFieldClassifier().classify([
    patternToken("Casey Rowan, CEO", id: "identity", y: 0.78, height: 0.08),
    patternToken("SAMPLE LABS", id: "organization", y: 0.60, height: 0.08),
  ])
  let cjkResult = try CardFieldClassifier().classify([
    patternToken("가상인 CEO", id: "identity", y: 0.78, height: 0.08, language: "ko"),
    patternToken("SAMPLE LABS", id: "organization", y: 0.60, height: 0.08),
  ])

  #expect(commaResult.fullName?.normalizedValue == "Casey Rowan")
  #expect(commaResult.jobTitle?.normalizedValue == "CEO")
  #expect(cjkResult.fullName?.normalizedValue == "가상인")
  #expect(cjkResult.jobTitle?.normalizedValue == "CEO")
}

@Test("Family-first comma notation remains one Latin person name")
func familyFirstCommaName() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Vale, Jordan Lee", id: "name", y: 0.78, height: 0.08),
    patternToken("Consultant", id: "title", y: 0.66),
    patternToken("SAMPLE GROUP", id: "organization", y: 0.54, height: 0.08),
  ])

  #expect(result.fullName?.normalizedValue == "Vale, Jordan Lee")
  #expect(result.jobTitle?.normalizedValue == "Consultant")
}

@Test("A department line cannot be joined onto an adjacent person name")
func departmentDoesNotJoinPersonName() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Avery Rowan", id: "name", x: 0.20, y: 0.84, width: 0.30, height: 0.08),
    patternToken(
      "Investment Team", id: "department", x: 0.20, y: 0.75, width: 0.32, height: 0.08),
    patternToken("Principal", id: "title", x: 0.60, y: 0.84, width: 0.22),
    patternToken("avery@sample.example", id: "email", y: 0.20),
    patternToken("SAMPLE VENTURES", id: "organization", y: 0.56, height: 0.08),
  ])

  #expect(result.fullName?.normalizedValue == "Avery Rowan")
  #expect(result.department?.normalizedValue == "Investment Team")
}

@Test("Initials plus surname in an email support a multipart Latin name")
func initialsAndSurnameEmailMatch() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Orange", id: "wordmark", y: 0.86, height: 0.09),
    patternToken("Seon-Tae Joo", id: "name", y: 0.72, height: 0.07),
    patternToken("CEO", id: "title", y: 0.62),
    patternToken("stjoo@example.example", id: "email", y: 0.22),
  ])

  #expect(result.fullName?.normalizedValue == "Seon-Tae Joo")
  #expect(result.fullName?.evidence.contains(.matchesEmailLocalPart) == true)
}

@Test("A short mixed-case wordmark is not promoted over a visible CJK person")
func mixedCaseWordmarkIsNotPerson() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("QaRTx", id: "wordmark", y: 0.86, height: 0.10),
    patternToken("가상인", id: "name", y: 0.72, height: 0.07, language: "ko"),
    patternToken("팀장", id: "title", y: 0.62, language: "ko"),
  ])

  #expect(result.fullName?.normalizedValue == "가상인")
  #expect(!result.alternateNames.map(\.normalizedValue).contains("QaRTx"))
}

@Test("An unsupported single-word Latin mark does not outrank a titled CJK person")
func titlecaseWordmarkDoesNotOutrankCJKPerson() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Citrine", id: "wordmark", y: 0.86, height: 0.10),
    patternToken("가상인", id: "name", y: 0.72, height: 0.07, language: "ko"),
    patternToken("CEO", id: "title", y: 0.62),
  ])

  #expect(result.fullName?.normalizedValue == "가상인")
  #expect(!result.alternateNames.map(\.normalizedValue).contains("Citrine"))
}

@Test("Repeated trailing OCR symbols do not erase an otherwise visible person")
func trailingOCRSymbolsAreIgnoredForIdentity() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Avery Rowan ###", id: "name", y: 0.80, height: 0.08),
    patternToken("Manager", id: "title", y: 0.68),
    patternToken("SAMPLE HOLDINGS", id: "organization", y: 0.54, height: 0.08),
  ])

  #expect(result.fullName?.normalizedValue == "Avery Rowan")
  #expect(result.fullName?.sourceTokenIdentifiers == ["name"])
}

@Test("One uppercase name component may coexist with a titlecase component and OCR noise")
func mixedCaseNameComponentsWithOCRNoise() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("SAMPLE HOLDINGS", id: "organization", y: 0.90, height: 0.09),
    patternToken("NOVA Weilin ###", id: "name", y: 0.80, height: 0.054),
    patternToken("Manager", id: "title", y: 0.70),
    patternToken("nova.weilin@example.example", id: "email", y: 0.22),
  ])

  #expect(result.fullName?.normalizedValue == "NOVA Weilin")
  #expect(result.fullName?.evidence.contains(.matchesEmailLocalPart) == true)
}

@Test("An organization-domain phrase is not promoted to a person")
func organizationDomainPhraseIsNotPerson() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Sample Harbor Investment", id: "organization", y: 0.84, height: 0.09),
    patternToken("Jordan Vale", id: "name", y: 0.70, height: 0.07),
    patternToken("Manager", id: "title", y: 0.60),
    patternToken("jordan@sampleharbor.example", id: "email", y: 0.20),
  ])

  #expect(result.fullName?.normalizedValue == "Jordan Vale")
  #expect(result.organization?.normalizedValue == "Sample Harbor Investment")
}

@Test("An anchored title remains a title when its functional remainder resembles an organization")
func anchoredTitleWinsOrganizationCollision() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Jordan Vale", id: "name", y: 0.84, height: 0.08),
    patternToken("Manager Customer Services & Solutions", id: "title", y: 0.72),
    patternToken("SAMPLE HOLDINGS", id: "organization", y: 0.56, height: 0.08),
  ])

  #expect(result.jobTitle?.normalizedValue == "Manager Customer Services & Solutions")
  #expect(result.organization?.normalizedValue == "SAMPLE HOLDINGS")
}

@Test("An explicit website survives beside an email while title notation is not a domain")
func mixedContactLineWebExtraction() throws {
  let result = try CardFieldClassifier().classify([
    patternToken(
      "Email demo@sample.example Web www.sample.example", id: "contacts", y: 0.30),
    patternToken("CEO.CTO", id: "roles", y: 0.50),
  ])

  #expect(result.emailAddresses.map(\.normalizedValue) == ["demo@sample.example"])
  #expect(result.websites.map(\.normalizedValue) == ["www.sample.example"])
  #expect(!result.websites.map(\.normalizedValue).contains("ceo.cto"))
}

@Test("Science parks and romanized Korean streets are address-shaped")
func expandedAddressPatterns() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("Science Park 608, Example City", id: "address-1", y: 0.44),
    patternToken("110-5, Fiction-ro, Sample-gu, Example City", id: "address-2", y: 0.32),
  ])

  #expect(result.addresses.map(\.normalizedValue).contains("Science Park 608, Example City"))
  #expect(
    result.addresses.map(\.normalizedValue).contains(
      "110-5, Fiction-ro, Sample-gu, Example City"))
}

@Test("Expanded title and department vocabulary remains field-specific")
func expandedProfessionalVocabulary() throws {
  let legalResult = try CardFieldClassifier().classify([
    patternToken("Avery Rowan", id: "name", y: 0.82),
    patternToken("CLO", id: "title", y: 0.70),
    patternToken("SAMPLE LABS", id: "organization", y: 0.56),
  ])
  let publicResult = try CardFieldClassifier().classify([
    patternToken("가상인", id: "name", y: 0.82, language: "ko"),
    patternToken("주무관", id: "title", y: 0.70, language: "ko"),
    patternToken("지역정책과/수출지원센터", id: "department", y: 0.58, language: "ko"),
    patternToken("가상정부기관", id: "organization", y: 0.46, language: "ko"),
  ])

  #expect(legalResult.jobTitle?.normalizedValue == "CLO")
  #expect(publicResult.jobTitle?.normalizedValue == "주무관")
  #expect(publicResult.department?.normalizedValue == "지역정책과/수출지원센터")
}

@Test("A parenthesized foundation marker remains organization evidence")
func parenthesizedFoundationMarker() throws {
  let result = try CardFieldClassifier().classify([
    patternToken("(재)샘플테크노파크", id: "organization", y: 0.78, height: 0.08, language: "ko"),
    patternToken("가상인", id: "name", y: 0.64, language: "ko"),
    patternToken("전문위원", id: "title", y: 0.54, language: "ko"),
  ])

  #expect(result.organization?.normalizedValue == "(재)샘플테크노파크")
  #expect(result.jobTitle?.normalizedValue == "전문위원")
}
