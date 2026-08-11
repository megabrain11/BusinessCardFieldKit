import CardFieldCore
import CardFieldEvaluation
import Foundation
import Testing

@Test("Evaluation JSON includes computed precision and recall")
func evaluationJSONIncludesRates() throws {
  let report = EvaluationReport(
    fixtureCount: 1,
    fields: [
      .fullName: FieldMetrics(truePositive: 2, falsePositive: 1, falseNegative: 2)
    ]
  )

  let data = try JSONEncoder().encode(report)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let fields = try #require(object["fields"] as? [String: Any])
  let fullName = try #require(fields[CardField.fullName.rawValue] as? [String: Any])

  #expect(fullName["precision"] as? Double == 2.0 / 3.0)
  #expect(fullName["recall"] as? Double == 0.5)
}
