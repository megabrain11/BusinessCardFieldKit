import CardFieldCore
import CardFieldEvaluation
import Foundation
import Testing

private func token(
  _ text: String,
  id: String = "",
  x: Double = 0.1,
  y: Double,
  width: Double = 0.7,
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

@Test("Korean identity, title, organization, and Korean phone labels are classified")
func koreanCard() throws {
  let result = try CardFieldClassifier().classify([
    token("김민서", y: 0.80, height: 0.09, language: "ko"),
    token("제품 팀장", y: 0.68, language: "ko"),
    token("새봄 연구소", y: 0.56, language: "ko"),
    token("휴대폰 010-5550-1200", y: 0.30, language: "ko"),
    token("전화 02-555-1100", y: 0.22, language: "ko"),
    token("팩스 02-555-1199", y: 0.14, language: "ko"),
  ])

  #expect(result.fullName?.normalizedValue == "김민서")
  #expect(result.jobTitle?.normalizedValue == "제품 팀장")
  #expect(result.organization?.normalizedValue == "새봄 연구소")
  #expect(result.mobilePhoneNumbers.map(\.normalizedValue) == ["01055501200"])
  #expect(result.workPhoneNumbers.map(\.normalizedValue) == ["025551100"])
  #expect(result.faxNumbers.map(\.normalizedValue) == ["025551199"])
}

@Test("English and long multipart names remain supported")
func internationalNames() throws {
  let result = try CardFieldClassifier().classify([
    token("María Fernanda de la Vega-Santos", y: 0.82, height: 0.09),
    token("Research Director", y: 0.70),
    token("NORTHSTAR FOUNDATION", y: 0.58),
    token("maria.vega@northstar.example", y: 0.20),
  ])

  #expect(result.fullName?.normalizedValue == "María Fernanda de la Vega-Santos")
  #expect(result.fullName?.evidence.contains(.matchesEmailLocalPart) == true)
}

@Test("Mixed Latin and CJK names are accepted and separate variants are retained")
func mixedNames() throws {
  let result = try CardFieldClassifier().classify([
    token("陳美玲 Mei-Ling Chen", y: 0.84, height: 0.09),
    token("Mei-Ling Chen", y: 0.75, height: 0.07),
    token("Design Director", y: 0.64),
    token("HARBOR STUDIO", y: 0.50),
  ])

  #expect(result.fullName?.normalizedValue == "陳美玲 Mei-Ling Chen")
  #expect(result.alternateNames.contains { $0.normalizedValue == "Mei-Ling Chen" })
}

@Test("A name and role on one line are split without losing source evidence")
func combinedNameAndRole() throws {
  let result = try CardFieldClassifier().classify([
    token("Jordan Rivera | Product Lead", id: "identity", y: 0.78, height: 0.09),
    token("ORBITAL WORKS", y: 0.55),
  ])

  #expect(result.fullName?.normalizedValue == "Jordan Rivera")
  #expect(result.jobTitle?.normalizedValue == "Product Lead")
  #expect(result.fullName?.sourceTokenIdentifiers == ["identity"])
}

@Test("Uppercase and numeric brands are organizations, never names")
func organizationBrands() throws {
  let uppercase = try CardFieldClassifier().classify([token("NORTHSTAR LABS", y: 0.8, height: 0.09)]
  )
  let numeric = try CardFieldClassifier().classify([token("STUDIO 42", y: 0.8, height: 0.09)])

  #expect(uppercase.organization?.normalizedValue == "NORTHSTAR LABS")
  #expect(uppercase.fullName == nil)
  #expect(numeric.organization?.normalizedValue == "STUDIO 42")
  #expect(numeric.fullName == nil)
}

@Test("Compact phone labels and multiple numbers retain their types")
func compactPhones() throws {
  let result = try CardFieldClassifier().classify([
    token("M: +1 202 555 0101", y: 0.50),
    token("C +1 202 555 0102", y: 0.42),
    token("O +1 202 555 0140", y: 0.34),
    token("D +1 202 555 0141", y: 0.26),
    token("F +1 202 555 0199", y: 0.18),
  ])

  #expect(result.mobilePhoneNumbers.count == 2)
  #expect(result.workPhoneNumbers.count == 2)
  #expect(result.faxNumbers.count == 1)
}

@Test("Bare domains, professional profiles, and social handles stay distinct")
func webFields() throws {
  let result = try CardFieldClassifier().classify([
    token("northstar.example", y: 0.40),
    token("linkedin.com/in/fictional-profile", y: 0.32),
    token("@fictional_handle", y: 0.24),
  ])

  #expect(result.websites.map(\.normalizedValue) == ["northstar.example"])
  #expect(result.professionalProfileURLs.count == 1)
  #expect(result.socialHandles.map(\.normalizedValue) == ["@fictional_handle"])
}

@Test("QR-heavy and organization-only cards do not invent people")
func noVisiblePerson() throws {
  let qrHeavy = try CardFieldClassifier().classify([
    token("Scan to connect", y: 0.70),
    token("qr-only.example", y: 0.20),
  ])
  let organizationOnly = try CardFieldClassifier().classify([
    token("NATIONAL RESEARCH INSTITUTE", y: 0.75, height: 0.10),
    token("research.example", y: 0.20),
  ])

  #expect(qrHeavy.fullName == nil)
  #expect(qrHeavy.warnings.contains(.noVisiblePersonName))
  #expect(organizationOnly.fullName == nil)
  #expect(organizationOnly.organization != nil)
}

@Test("Government, university, association, foundation, and research organizations are recognized")
func institutionOrganizations() throws {
  for organization in [
    "Ministry of Fictional Affairs", "Example State University", "Robotics Association",
    "Open Knowledge Foundation", "새봄 연구원",
  ] {
    let result = try CardFieldClassifier().classify([token(organization, y: 0.8, height: 0.08)])
    #expect(result.organization?.normalizedValue == organization)
    #expect(result.fullName == nil)
  }
}

@Test("Slogans and taglines remain unclassified instead of becoming identity fields")
func sloganExclusion() throws {
  let result = try CardFieldClassifier().classify([
    token("Building the future together", y: 0.8, height: 0.08),
    token("Creating value for everyone", y: 0.6),
  ])

  #expect(result.fullName == nil)
  #expect(result.organization == nil)
  #expect(result.unclassifiedLines.count == 2)
}

@Test("Addresses from multiple countries are classified")
func internationalAddresses() throws {
  let result = try CardFieldClassifier().classify([
    token("120 Fictional Avenue, Toronto, ON M5V 2T6", y: 0.50),
    token("서울특별시 새봄구 열린로 42, 7층", y: 0.40, language: "ko"),
    token("10 Example Road, London SW1A 2AA", y: 0.30),
  ])

  #expect(result.addresses.count == 3)
}

@Test("Low-confidence ambiguous text remains unresolved")
func lowConfidenceAmbiguity() throws {
  let result = try CardFieldClassifier().classify([
    token("River Stone", y: 0.50, height: 0.03, confidence: 0.25)
  ])

  #expect(result.fullName == nil)
  #expect(result.unclassifiedLines.count == 1)
  #expect(result.warnings.contains(.noVisiblePersonName))
}

@Test("Locale packs extend base rules without mutating them")
func localeRulePack() throws {
  let pack = RulePack(
    identifier: "example.locale",
    version: "1.0.0",
    locale: "en-XA",
    organizationSuffixes: ["Guildhouse"],
    jobTitles: ["Wayfinder"]
  )
  let observations = [
    token("Taylor Morgan", y: 0.80, height: 0.09),
    token("Wayfinder", y: 0.68),
    token("North Guildhouse", y: 0.56),
  ]
  let withoutPack = try CardFieldClassifier().classify(observations)
  let withPack = try CardFieldClassifier(rulePacks: [pack]).classify(observations)

  #expect(withoutPack.jobTitle == nil)
  #expect(withPack.jobTitle?.normalizedValue == "Wayfinder")
  #expect(withPack.organization?.normalizedValue == "North Guildhouse")
}

@Test("Personal corrections have highest priority and remain outside base rules")
func personalCorrections() throws {
  let corrections = InMemoryCorrectionStore(corrections: [
    .init(
      id: "domain",
      kind: .emailDomainOrganization,
      match: "fictional.example",
      replacement: "Fictional Cooperative"
    ),
    .init(
      id: "title",
      kind: .customJobTitle,
      match: "Pathfinder"
    ),
    .init(
      id: "preferred",
      kind: .preferredNameOrdering,
      match: "Morgan Taylor",
      replacement: "Taylor Morgan"
    ),
  ])
  let observations = [
    token("Morgan Taylor", y: 0.80, height: 0.09),
    token("Pathfinder", y: 0.68),
    token("morgan.taylor@fictional.example", y: 0.20),
  ]
  let corrected = try CardFieldClassifier(correctionStore: corrections).classify(observations)
  let base = try CardFieldClassifier().classify(observations)

  #expect(corrected.organization?.normalizedValue == "Fictional Cooperative")
  #expect(corrected.organization?.evidence.contains(.userCorrection) == true)
  #expect(corrected.jobTitle?.normalizedValue == "Pathfinder")
  #expect(corrected.preferredName?.normalizedValue == "Taylor Morgan")
  #expect(base.organization == nil)
  #expect(base.jobTitle == nil)
  #expect(base.preferredName == nil)
}

@Test("Sanitized contribution drafts contain placeholders and no original values")
func contributionSanitizer() throws {
  let observations = [
    token("Avery Rowan", y: 0.8, height: 0.09),
    token("avery.rowan@fictional.example", y: 0.4),
    token("120 Fictional Road", y: 0.2),
  ]
  let result = try CardFieldClassifier().classify(observations)
  let correction = PersonalCorrection(
    id: "private-rule",
    kind: .organizationAlias,
    match: "Secret Alias",
    replacement: "Private Organization"
  )
  let draft = ContributionSanitizer.makeDraft(
    observations: observations,
    result: result,
    corrections: [correction]
  )
  let data = try JSONEncoder().encode(draft)
  let json = String(decoding: data, as: UTF8.self)

  for privateValue in observations.map(\.text) + [correction.match, correction.replacement!] {
    #expect(!json.contains(privateValue))
  }
  #expect(json.contains("<PERSON_NAME>"))
  #expect(json.contains("<EMAIL>"))
}

@Test("Classification is deterministic for the same input and rule versions")
func deterministicClassification() throws {
  let observations = [
    token("Casey Winter", y: 0.8, height: 0.09),
    token("Software Engineer", y: 0.65),
    token("EVERGREEN SYSTEMS", y: 0.5),
  ]
  let classifier = CardFieldClassifier()
  #expect(try classifier.classify(observations) == classifier.classify(observations))
}

@Test("Evaluation runner reports field-level precision and recall")
func evaluationRunner() throws {
  let fixture = EvaluationFixture(
    identifier: "evaluation-example",
    observations: [
      token("Jamie Sol", y: 0.8, height: 0.09),
      token("Design Lead", y: 0.65),
    ],
    expected: [.fullName: ["Jamie Sol"], .jobTitle: ["Design Lead"]]
  )
  let report = try FixtureRunner.evaluate([fixture])
  #expect(report.metrics(for: .fullName)?.precision == 1)
  #expect(report.metrics(for: .jobTitle)?.recall == 1)
}

@Test("Mixed Korean and English identity text remains a person candidate")
func mixedKoreanEnglishName() throws {
  let result = try CardFieldClassifier().classify([
    token("김민서 Minseo Kim", y: 0.80, height: 0.09),
    token("Product Manager", y: 0.66),
  ])

  #expect(result.fullName?.normalizedValue == "김민서 Minseo Kim")
  #expect(result.fullName?.evidence.contains(.multilingualVariant) == true)
}

@Test("Department vocabulary remains separate from title and organization")
func departmentClassification() throws {
  let result = try CardFieldClassifier().classify([
    token("Riley Quinn", y: 0.82, height: 0.09),
    token("Senior Engineer", y: 0.70),
    token("Research Department", y: 0.60),
    token("NORTHSTAR LABS", y: 0.48),
  ])

  #expect(result.department?.normalizedValue == "Research Department")
  #expect(result.jobTitle?.normalizedValue == "Senior Engineer")
  #expect(result.organization?.normalizedValue == "NORTHSTAR LABS")
}

@Test("Repository JSON examples decode through their public contracts")
func repositoryJSONExamplesDecode() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let decoder = JSONDecoder()

  for name in ["ko-KR.json", "research.json"] {
    let data = try Data(contentsOf: repository.appendingPathComponent("Rules/\(name)"))
    _ = try decoder.decode(RulePack.self, from: data)
  }

  let corrections = try Data(
    contentsOf: repository.appendingPathComponent("Examples/Corrections/local-corrections.json")
  )
  _ = try decoder.decode([PersonalCorrection].self, from: corrections)

  let fixtures = try Data(
    contentsOf: repository.appendingPathComponent("Fixtures/Synthetic/phase1.json")
  )
  #expect(try FixtureRunner.decode(data: fixtures).count == 3)

  let schemaDirectory = repository.appendingPathComponent("Schemas")
  for name in [
    "ocr-input.schema.json", "classification-output.schema.json", "rule-pack.schema.json",
    "contribution-draft.schema.json",
  ] {
    let data = try Data(contentsOf: schemaDirectory.appendingPathComponent(name))
    #expect(try JSONSerialization.jsonObject(with: data) is [String: Any])
  }
}
