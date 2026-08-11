import CardFieldCore
import CardFieldEvaluation
import Foundation
import Testing

private let publicAlphaRepository = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()

@Test("Public alpha fixtures decode and match every expected field")
func publicAlphaFixturesEvaluateWithoutFieldErrors() throws {
  let data = try Data(
    contentsOf: publicAlphaRepository.appendingPathComponent(
      "Fixtures/Synthetic/public-alpha.json"
    )
  )
  let fixtures = try FixtureRunner.decode(data: data)

  #expect(fixtures.count == 26)
  #expect(Set(fixtures.map(\.identifier)).count == fixtures.count)
  #expect(fixtures.allSatisfy { $0.identifier.hasPrefix("public-alpha-") })

  let knownFields = Set(CardField.allCases.map(\.rawValue))
  #expect(fixtures.allSatisfy { Set($0.expected.keys).isSubset(of: knownFields) })

  let report = try FixtureRunner.evaluate(fixtures)
  #expect(report.fixtureCount == fixtures.count)
  for field in CardField.allCases {
    #expect(report.metrics(for: field)?.falsePositive == 0)
    #expect(report.metrics(for: field)?.falseNegative == 0)
  }
}

@Test("Public alpha fixture contact values use synthetic namespaces")
func publicAlphaFixtureContactValuesAreSynthetic() throws {
  let data = try Data(
    contentsOf: publicAlphaRepository.appendingPathComponent(
      "Fixtures/Synthetic/public-alpha.json"
    )
  )
  let fixtures = try FixtureRunner.decode(data: data)

  let emails = fixtures.flatMap { $0.expected[CardField.emailAddresses.rawValue] ?? [] }
  let websites = fixtures.flatMap { $0.expected[CardField.websites.rawValue] ?? [] }
  let profiles = fixtures.flatMap {
    $0.expected[CardField.professionalProfileURLs.rawValue] ?? []
  }

  #expect(emails.allSatisfy { $0.hasSuffix(".example") })
  #expect(websites.allSatisfy { $0.hasSuffix(".example") })
  #expect(profiles.allSatisfy { $0.contains("public-alpha-") })
}
