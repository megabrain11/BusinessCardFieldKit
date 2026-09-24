import CardFieldCore
import Foundation
import Testing

@Suite("Column-aware classifier")
struct ColumnAwareClassifierTests {
  private func token(
    _ id: String,
    _ text: String,
    x: Double,
    y: Double,
    width: Double,
    height: Double = 0.06,
    confidence: Double = 0.95
  ) -> OCRToken {
    OCRToken(
      id: id,
      text: text,
      boundingBox: NormalizedBoundingBox(x: x, y: y, width: width, height: height),
      confidence: confidence
    )
  }

  private func separatedPhoneRow(
    prefix: String,
    label: String,
    number: String,
    y: Double,
    confidence: Double = 0.95
  ) -> [OCRToken] {
    [
      token("\(prefix)-label", label, x: 0.05, y: y, width: 0.04, confidence: confidence),
      token("\(prefix)-gap", "•", x: 0.20, y: y, width: 0.05, confidence: confidence),
      token("\(prefix)-value", number, x: 0.55, y: y, width: 0.32, confidence: confidence),
    ]
  }

  private func enabledClassifier(
    strategy: ColumnAwareClassifierOptions.Strategy = .conservative
  ) -> CardFieldClassifier {
    CardFieldClassifier(
      columnAwareOptions: ColumnAwareClassifierOptions(mode: .enabled, strategy: strategy)
    )
  }

  @Test("Disabled mode preserves the legacy result and emits no diagnostics")
  func disabledModePreservesLegacyResult() throws {
    let tokens = separatedPhoneRow(
      prefix: "mobile",
      label: "M",
      number: "+1 202 555 0101",
      y: 0.70
    )
    let legacy = try CardFieldClassifier().classify(tokens)
    let disabled = try CardFieldClassifier(
      columnAwareOptions: ColumnAwareClassifierOptions(mode: .disabled)
    ).classifyWithDiagnostics(tokens)

    #expect(disabled.result == legacy)
    #expect(disabled.diagnostics == nil)
    #expect(legacy.mobilePhoneNumbers.isEmpty)
  }

  @Test("Separated columns recover a mobile number the legacy pass leaves unresolved")
  func sameRowAcrossColumnsRecoversMobile() throws {
    let tokens = separatedPhoneRow(
      prefix: "mobile",
      label: "M",
      number: "+1 202 555 0101",
      y: 0.70
    )
    let output = try enabledClassifier().classifyWithDiagnostics(tokens)

    #expect(output.result.mobilePhoneNumbers.map(\.normalizedValue) == ["+12025550101"])
    #expect(output.diagnostics?.multiColumnRowCount == 1)
    #expect(output.diagnostics?.candidateCount == 1)
    #expect(output.diagnostics?.recoveredValueCount == 1)
    #expect(output.diagnostics?.usedFallback == false)
  }

  @Test("Adjacent vertically aligned rows recover a labeled phone")
  func adjacentRowsRecoverPhone() throws {
    let tokens = [
      token("label", "Tel", x: 0.05, y: 0.74, width: 0.06),
      token("gap", "•", x: 0.42, y: 0.74, width: 0.05),
      token("value", "+1 303 555 0102", x: 0.05, y: 0.63, width: 0.30),
    ]
    let output = try enabledClassifier().classifyWithDiagnostics(tokens)

    #expect(output.result.workPhoneNumbers.map(\.normalizedValue) == ["+13035550102"])
    #expect(output.diagnostics?.recoveredValueCount == 1)
  }

  @Test("English and Korean labels retain mobile work and fax subtypes")
  func multilingualSubtypeRecovery() throws {
    let tokens =
      separatedPhoneRow(
        prefix: "mobile",
        label: "휴대폰",
        number: "010-5550-0103",
        y: 0.78
      )
      + separatedPhoneRow(
        prefix: "work",
        label: "Tel",
        number: "+1 404 555 0104",
        y: 0.62
      )
      + separatedPhoneRow(
        prefix: "fax",
        label: "팩스",
        number: "+1 404 555 0105",
        y: 0.46
      )
    let output = try enabledClassifier().classifyWithDiagnostics(tokens)

    #expect(output.result.mobilePhoneNumbers.map(\.normalizedValue) == ["01055500103"])
    #expect(output.result.workPhoneNumbers.map(\.normalizedValue) == ["+14045550104"])
    #expect(output.result.faxNumbers.map(\.normalizedValue) == ["+14045550105"])
    #expect(output.diagnostics?.recoveredValueCount == 3)
  }

  @Test("Multiple labels of one subtype can recover distinct numbers")
  func multipleLabelsRecoverDistinctNumbers() throws {
    let tokens =
      separatedPhoneRow(
        prefix: "first",
        label: "M",
        number: "+1 505 555 0106",
        y: 0.75
      )
      + separatedPhoneRow(
        prefix: "second",
        label: "Mobile",
        number: "+1 505 555 0107",
        y: 0.52
      )
    let output = try enabledClassifier().classifyWithDiagnostics(tokens)

    #expect(
      Set(output.result.mobilePhoneNumbers.map(\.normalizedValue))
        == ["+15055550106", "+15055550107"]
    )
    #expect(output.diagnostics?.recoveredValueCount == 2)
  }

  @Test("Tied candidates require review and recover neither value")
  func tiedCandidatesRequireReview() throws {
    let tokens = [
      token("label", "M", x: 0.05, y: 0.70, width: 0.04),
      token("gap", "•", x: 0.20, y: 0.70, width: 0.05),
      token("value-a", "+1 606 555 0108", x: 0.55, y: 0.70, width: 0.30),
      token("value-b", "+1 606 555 0109", x: 0.55, y: 0.70, width: 0.30),
    ]
    let output = try enabledClassifier().classifyWithDiagnostics(tokens)

    #expect(output.result.mobilePhoneNumbers.isEmpty)
    #expect(output.result.warnings.contains(.ambiguousPhoneNumber))
    #expect(output.result.warnings.contains(.reviewRecommended))
    #expect(output.diagnostics?.conflictCount == 1)
    #expect(output.diagnostics?.recoveredValueCount == 0)
  }

  @Test("Low-confidence layouts fail closed to the legacy result")
  func lowConfidenceLayoutFallsBack() throws {
    let tokens = separatedPhoneRow(
      prefix: "mobile",
      label: "M",
      number: "+1 707 555 0110",
      y: 0.70,
      confidence: 0.20
    )
    let legacy = try CardFieldClassifier().classify(tokens)
    let output = try enabledClassifier().classifyWithDiagnostics(tokens)

    #expect(output.result == legacy)
    #expect(output.diagnostics?.usedFallback == true)
    #expect(output.diagnostics?.fallbackReason == "low-layout-confidence")
  }

  @Test("Different label kinds competing for one value require review")
  func subtypeConflictRequiresReview() throws {
    let tokens = [
      token("mobile-label", "M", x: 0.05, y: 0.70, width: 0.04),
      token("fax-label", "Fax", x: 0.20, y: 0.70, width: 0.07),
      token("gap", "•", x: 0.38, y: 0.70, width: 0.04),
      token("value", "+1 717 555 0115", x: 0.60, y: 0.70, width: 0.30),
    ]
    let output = try enabledClassifier().classifyWithDiagnostics(tokens)

    #expect(
      output.result.mobilePhoneNumbers.count + output.result.faxNumbers.count == 1
    )
    #expect(output.result.warnings.contains(.ambiguousPhoneNumber))
    #expect(output.result.warnings.contains(.reviewRecommended))
    #expect(output.diagnostics?.conflictCount == 1)
  }

  @Test("Invalid geometry cannot create a layout-derived value")
  func invalidGeometryFallsBack() throws {
    let tokens = [
      token("label", "M", x: 0.05, y: 0.70, width: 0.04),
      token("value", "+1 808 555 0111", x: 0.90, y: 0.70, width: 0.30),
    ]
    let output = try enabledClassifier().classifyWithDiagnostics(tokens)

    #expect(output.result.mobilePhoneNumbers.isEmpty)
    #expect(output.result.warnings.contains(.invalidBoundingBox))
    #expect(output.diagnostics?.usedFallback == true)
    #expect(output.diagnostics?.fallbackReason == "no-linkable-candidates")
  }

  @Test("Shuffled observations produce identical results and diagnostics")
  func shuffledInputIsDeterministic() throws {
    let tokens = separatedPhoneRow(
      prefix: "mobile",
      label: "M",
      number: "+1 909 555 0112",
      y: 0.70
    )
    let forward = try enabledClassifier().classifyWithDiagnostics(tokens)
    let reversed = try enabledClassifier().classifyWithDiagnostics(Array(tokens.reversed()))

    #expect(forward == reversed)
  }

  @Test("Legacy-classified numbers are not added twice")
  func existingPhoneIsNotDuplicated() throws {
    let tokens = [
      token("label", "M", x: 0.05, y: 0.70, width: 0.04),
      token("value", "+1 212 555 0113", x: 0.14, y: 0.70, width: 0.30),
    ]
    let output = try enabledClassifier().classifyWithDiagnostics(tokens)

    #expect(output.result.mobilePhoneNumbers.map(\.normalizedValue) == ["+12125550113"])
    #expect(output.diagnostics?.candidateCount == 1)
    #expect(output.diagnostics?.recoveredValueCount == 0)
  }

  @Test("Column relationships are exposed by the scoring engine")
  func scoringEngineUsesColumnRuns() {
    let tokens = separatedPhoneRow(
      prefix: "mobile",
      label: "M",
      number: "+1 313 555 0114",
      y: 0.70
    )
    let labels = [
      ColumnAwarePhoneLabel(text: "M", kind: .mobile, tokenIdentifier: "mobile-label")
    ]
    let candidates = ColumnAwareScoringEngine.candidates(for: tokens, labels: labels)

    #expect(candidates.first?.relationship == .sameRowAcrossColumns)
  }

  @Test("Diagnostics preserve their additive JSON representation")
  func diagnosticsRoundTripThroughJSON() throws {
    let original = ColumnAwareDiagnostics(
      mode: "enabled",
      strategy: "conservative",
      layoutConfidence: 0.91,
      rowCount: 3,
      multiColumnRowCount: 1,
      candidateCount: 2,
      recoveredValueCount: 1,
      conflictCount: 0,
      usedFallback: false
    )

    let decoded = try JSONDecoder().decode(
      ColumnAwareDiagnostics.self,
      from: JSONEncoder().encode(original)
    )
    #expect(decoded == original)
  }
}
