import CardFieldCore
import Foundation
import Testing

private func strictToken(
  _ text: String,
  id: String,
  y: Double,
  confidence: Double = 0.94,
  alternatives: [String] = []
) -> OCRToken {
  OCRToken(
    id: id,
    text: text,
    boundingBox: .init(x: 0.1, y: y, width: 0.75, height: 0.06),
    confidence: confidence,
    alternatives: alternatives
  )
}

private func strictClassifier() -> CardFieldClassifier {
  CardFieldClassifier(
    strictFieldCorrectionOptions: StrictFieldCorrectionOptions(mode: .enabled)
  )
}

@Test("Strict-field correction is disabled by default and preserves legacy results")
func strictFieldCorrectionDisabledParity() throws {
  let observations = [
    strictToken(
      "Email: avery@harbor.c0m",
      id: "email",
      y: 0.5,
      alternatives: ["Email: avery@harbor.example"]
    ),
    strictToken(
      "Mobile: O1O-555O-1200",
      id: "phone",
      y: 0.4,
      alternatives: ["Mobile: 010-5550-1200"]
    ),
  ]

  let implicit = try CardFieldClassifier().classify(observations)
  let explicit = try CardFieldClassifier(
    strictFieldCorrectionOptions: StrictFieldCorrectionOptions(mode: .disabled)
  ).classify(observations)

  #expect(implicit == explicit)
  #expect(implicit.emailAddresses.isEmpty)
  #expect(implicit.mobilePhoneNumbers.isEmpty)
}

@Test("A unique syntax-valid email alternative replaces a suspicious reading")
func strictEmailAlternativeRecovery() throws {
  let result = try strictClassifier().classify([
    strictToken(
      "Email: avery@harbor.con",
      id: "email",
      y: 0.5,
      alternatives: ["Email: avery@harbor.example"]
    )
  ])

  #expect(result.emailAddresses.map(\.normalizedValue) == ["avery@harbor.example"])
  #expect(result.emailAddresses.first?.originalValue == "avery@harbor.example")
  #expect(!result.warnings.contains(.reviewRecommended))
}

@Test("A unique syntax-valid website alternative replaces a suspicious reading")
func strictWebsiteAlternativeRecovery() throws {
  let result = try strictClassifier().classify([
    strictToken(
      "Web: www.harbor.c0m",
      id: "website",
      y: 0.5,
      alternatives: ["Web: www.harbor.example"]
    )
  ])

  #expect(result.websites.map(\.normalizedValue) == ["www.harbor.example"])
  #expect(!result.warnings.contains(.reviewRecommended))
}

@Test("A unique syntax-valid phone alternative retains its printed subtype")
func strictPhoneAlternativeRecovery() throws {
  let result = try strictClassifier().classify([
    strictToken(
      "Mobile: O1O-555O-1200",
      id: "phone",
      y: 0.5,
      alternatives: ["Mobile: 010-5550-1200"]
    )
  ])

  #expect(result.mobilePhoneNumbers.map(\.normalizedValue) == ["01055501200"])
  #expect(result.workPhoneNumbers.isEmpty)
  #expect(result.faxNumbers.isEmpty)
}

@Test("Duplicate alternatives with one normalized value are not ambiguous")
func duplicateStrictAlternativesCollapse() throws {
  let result = try strictClassifier().classify([
    strictToken(
      "Email: avery@harbor.c0m",
      id: "email",
      y: 0.5,
      alternatives: [
        "Email: Avery@Harbor.Example",
        "email: avery@harbor.example",
        "Email: Avery@Harbor.Example",
      ]
    )
  ])

  #expect(result.emailAddresses.map(\.normalizedValue) == ["avery@harbor.example"])
  #expect(!result.warnings.contains(.reviewRecommended))
}

@Test("Multiple valid alternatives retain the original and require review")
func tiedStrictAlternativesRequireReview() throws {
  let result = try strictClassifier().classify([
    strictToken(
      "Email: avery@harbor.c0m",
      id: "email",
      y: 0.5,
      alternatives: [
        "Email: avery@harbor.example",
        "Email: avery@harbour.example",
      ]
    )
  ])

  #expect(result.emailAddresses.isEmpty)
  #expect(result.warnings.contains(.reviewRecommended))
}

@Test("A valid original wins over a different valid alternative and requires review")
func validStrictOriginalIsNeverReplaced() throws {
  let result = try strictClassifier().classify([
    strictToken(
      "Email: avery@harbor.example",
      id: "email",
      y: 0.5,
      alternatives: ["Email: avery@harbour.example"]
    )
  ])

  #expect(result.emailAddresses.map(\.normalizedValue) == ["avery@harbor.example"])
  #expect(result.warnings.contains(.reviewRecommended))
}

@Test("Invalid alternatives are ignored without changing the original")
func invalidStrictAlternativesAreIgnored() throws {
  let result = try strictClassifier().classify([
    strictToken(
      "Email: avery@harbor.c0m",
      id: "email",
      y: 0.5,
      alternatives: ["Avery Harbor", "Email address unavailable"]
    )
  ])

  #expect(result.emailAddresses.isEmpty)
  #expect(!result.warnings.contains(.reviewRecommended))
}

@Test("A phone alternative cannot change the printed subtype label")
func phoneAlternativeCannotChangeSubtype() throws {
  let result = try strictClassifier().classify([
    strictToken(
      "Mobile: O1O-555O-1200",
      id: "phone",
      y: 0.5,
      alternatives: ["Fax: 010-5550-1200"]
    )
  ])

  #expect(result.mobilePhoneNumbers.isEmpty)
  #expect(result.faxNumbers.isEmpty)
  #expect(!result.warnings.contains(.reviewRecommended))
}

@Test("Low-confidence observations are retained and routed to review")
func lowConfidenceStrictAlternativeRequiresReview() throws {
  let observations = [
    strictToken(
      "Web: www.harbor.c0m",
      id: "website",
      y: 0.5,
      confidence: 0.40,
      alternatives: ["Web: www.harbor.example"]
    )
  ]
  let legacy = try CardFieldClassifier().classify(observations)
  let result = try strictClassifier().classify(observations)

  #expect(result.websites == legacy.websites)
  #expect(result.warnings.contains(.reviewRecommended))
}

@Test("Conflicting local and international phone alternatives require review")
func countryCodeConflictRequiresReview() throws {
  let result = try strictClassifier().classify([
    strictToken(
      "Mobile: O1O-555O-1200",
      id: "phone",
      y: 0.5,
      alternatives: [
        "Mobile: 010-5550-1200",
        "Mobile: +82 10-5550-1200",
      ]
    )
  ])

  #expect(result.mobilePhoneNumbers.isEmpty)
  #expect(result.warnings.contains(.ambiguousPhoneNumber))
  #expect(result.warnings.contains(.reviewRecommended))
}

@Test("Free-text alternatives never change identity or organization fields")
func freeTextAlternativesRemainUnused() throws {
  let observations = [
    strictToken(
      "Avery Stone",
      id: "name",
      y: 0.8,
      alternatives: ["Avery Stowe", "Harbor Works"]
    ),
    strictToken(
      "Product Director",
      id: "title",
      y: 0.7,
      alternatives: ["Product Designer"]
    ),
    strictToken(
      "HARBOR WORKS",
      id: "organization",
      y: 0.6,
      alternatives: ["HARBOR WORDS"]
    ),
  ]

  let legacy = try CardFieldClassifier().classify(observations)
  let enabled = try strictClassifier().classify(observations)

  #expect(enabled == legacy)
}

@Test("Corrected email evidence cannot reclassify free-text fields")
func correctedEmailDoesNotInfluenceFreeTextClassification() throws {
  let observations = [
    strictToken("Avery Stone", id: "name", y: 0.8),
    strictToken("Product Director", id: "title", y: 0.7),
    strictToken("HARBOR WORKS", id: "organization", y: 0.6),
    strictToken(
      "Email: avery.stone@harbor.c0m",
      id: "email",
      y: 0.3,
      alternatives: ["Email: avery.stone@harbor.example"]
    ),
  ]

  let legacy = try CardFieldClassifier().classify(observations)
  let enabled = try strictClassifier().classify(observations)

  #expect(enabled.fullName == legacy.fullName)
  #expect(enabled.jobTitle == legacy.jobTitle)
  #expect(enabled.organization == legacy.organization)
  #expect(enabled.emailAddresses.map(\.normalizedValue) == ["avery.stone@harbor.example"])
}

@Test("Strict correction is deterministic for shuffled token and alternative input")
func strictCorrectionIsDeterministic() throws {
  let observations = [
    strictToken(
      "Email: avery@harbor.c0m",
      id: "email",
      y: 0.5,
      alternatives: ["Email: avery@harbor.example", "Email: Avery@Harbor.Example"]
    ),
    strictToken(
      "Web: www.harbor.c0m",
      id: "website",
      y: 0.4,
      alternatives: ["Web: www.harbor.example"]
    ),
  ]
  var reversed = Array(observations.reversed())
  reversed[0].alternatives.reverse()
  reversed[1].alternatives.reverse()

  let forwardResult = try strictClassifier().classify(observations)
  let reversedResult = try strictClassifier().classify(reversed)

  #expect(forwardResult == reversedResult)
}
