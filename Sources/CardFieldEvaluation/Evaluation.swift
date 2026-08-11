import CardFieldCore
import Foundation

public struct EvaluationFixture: Codable, Equatable, Sendable {
  public var identifier: String
  public var observations: [OCRToken]
  public var expected: [String: [String]]

  public init(identifier: String, observations: [OCRToken], expected: [CardField: [String]]) {
    self.identifier = identifier
    self.observations = observations
    self.expected = Dictionary(uniqueKeysWithValues: expected.map { ($0.key.rawValue, $0.value) })
  }
}

public struct FieldMetrics: Codable, Equatable, Sendable {
  public var truePositive: Int
  public var falsePositive: Int
  public var falseNegative: Int

  public var precision: Double {
    let denominator = truePositive + falsePositive
    return denominator == 0 ? 1 : Double(truePositive) / Double(denominator)
  }

  public var recall: Double {
    let denominator = truePositive + falseNegative
    return denominator == 0 ? 1 : Double(truePositive) / Double(denominator)
  }

  public init(truePositive: Int = 0, falsePositive: Int = 0, falseNegative: Int = 0) {
    self.truePositive = truePositive
    self.falsePositive = falsePositive
    self.falseNegative = falseNegative
  }

  private enum CodingKeys: String, CodingKey {
    case truePositive
    case falsePositive
    case falseNegative
    case precision
    case recall
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    truePositive = try container.decode(Int.self, forKey: .truePositive)
    falsePositive = try container.decode(Int.self, forKey: .falsePositive)
    falseNegative = try container.decode(Int.self, forKey: .falseNegative)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(truePositive, forKey: .truePositive)
    try container.encode(falsePositive, forKey: .falsePositive)
    try container.encode(falseNegative, forKey: .falseNegative)
    try container.encode(precision, forKey: .precision)
    try container.encode(recall, forKey: .recall)
  }
}

public struct EvaluationReport: Codable, Equatable, Sendable {
  public var fixtureCount: Int
  public var fields: [String: FieldMetrics]

  public init(fixtureCount: Int, fields: [CardField: FieldMetrics]) {
    self.fixtureCount = fixtureCount
    self.fields = Dictionary(uniqueKeysWithValues: fields.map { ($0.key.rawValue, $0.value) })
  }

  public func metrics(for field: CardField) -> FieldMetrics? {
    fields[field.rawValue]
  }
}

public enum FixtureRunner {
  public static func decode(data: Data) throws -> [EvaluationFixture] {
    try JSONDecoder().decode([EvaluationFixture].self, from: data)
  }

  public static func evaluate(
    _ fixtures: [EvaluationFixture],
    classifier: CardFieldClassifier = CardFieldClassifier()
  ) throws -> EvaluationReport {
    var metrics = Dictionary(uniqueKeysWithValues: CardField.allCases.map { ($0, FieldMetrics()) })
    for fixture in fixtures {
      let result = try classifier.classify(fixture.observations)
      for field in CardField.allCases {
        let expected = Set((fixture.expected[field.rawValue] ?? []).map(normalized))
        let actual = Set(result.values(for: field).map { normalized($0.normalizedValue) })
        let overlap = expected.intersection(actual).count
        metrics[field]?.truePositive += overlap
        metrics[field]?.falsePositive += actual.subtracting(expected).count
        metrics[field]?.falseNegative += expected.subtracting(actual).count
      }
    }
    return EvaluationReport(fixtureCount: fixtures.count, fields: metrics)
  }

  private static func normalized(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .lowercased().filter { !$0.isWhitespace }
  }
}
