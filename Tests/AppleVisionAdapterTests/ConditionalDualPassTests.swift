import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics

  @Test("Conditional dual-pass defaults disabled and clamps thresholds")
  func conditionalDualPassDefaultsAndClamping() {
    let defaults = AppleVisionConditionalDualPassOptions()
    #expect(defaults.mode == .disabled)
    #expect(defaults.minimumLineConfidence == 0.82)

    let clamped = AppleVisionConditionalDualPassOptions(
      mode: .enabled,
      minimumLineConfidence: 2,
      contentEdgeMargin: -1
    )
    #expect(clamped.minimumLineConfidence == 1)
    #expect(clamped.contentEdgeMargin == 0)
  }

  @Test("Complete high-confidence contacts are eligible independent of input order")
  func conditionalDualPassEligibilityIsOrderIndependent() {
    let lines = eligibleLines()
    let forward = decision(lines)
    let reverse = decision(Array(lines.reversed()))

    #expect(forward == .eligible)
    #expect(reverse == forward)
  }

  @Test(
    "Conditional dual-pass rejects unsafe recognition evidence",
    arguments: [
      unsafeCase(.fullImageFallback, eligibleLines(), .fullImageFallback),
      unsafeCase(
        .isolatedCard, eligibleLines(), .targetedRecognition, role: .targetedReRecognition),
      unsafeCase(
        .isolatedCard,
        replacing(eligibleLines(), at: 0, with: line("Morgan Vale", y: 0.82, confidence: 0.6)),
        .lowConfidence
      ),
      unsafeCase(
        .isolatedCard,
        replacing(eligibleLines(), at: 0, with: line("모건 Vale", y: 0.82)),
        .multilingualEvidence
      ),
      unsafeCase(
        .isolatedCard,
        [
          line("morgan@cascade.example", x: 0.08, y: 0.60, width: 0.36),
          line("Mobile +1 202 555 0147", x: 0.58, y: 0.60, width: 0.32),
        ],
        .complexLayout
      ),
      unsafeCase(
        .isolatedCard,
        replacing(
          eligibleLines(), at: 0,
          with: line("Morgan Vale", x: 0.001, y: 0.82, width: 0.35)),
        .croppedContent
      ),
      unsafeCase(
        .isolatedCard,
        replacing(
          eligibleLines(), at: 1,
          with: line(
            "morgan@cascade.example", y: 0.60,
            alternatives: ["morgan@cascad3.example"])),
        .ambiguousAlternatives
      ),
      unsafeCase(
        .isolatedCard,
        replacing(
          eligibleLines(), at: 2,
          with: line(
            "Mobile +1 202 555 0147", y: 0.38,
            alternatives: ["Mobile 202 555 0147"])),
        .countryCodeConflict
      ),
      unsafeCase(
        .isolatedCard,
        [line("morgan@cascade.example", y: 0.60)],
        .insufficientStrictContact
      ),
      unsafeCase(
        .isolatedCard,
        [
          line("Morgan Avery", y: 0.88),
          line("Avery Morgan", y: 0.78),
          line("Chief Executive Officer", y: 0.68),
          line("CASCADE LABS", y: 0.58),
          line("contact@cascade.example", y: 0.44),
          line("Mobile +1 202 555 0147", y: 0.30),
        ],
        .reviewRecommended
      ),
    ])
  func conditionalDualPassRejectsUnsafeEvidence(testCase: UnsafeCase) {
    #expect(
      decision(testCase.lines, context: testCase.context, role: testCase.role)
        == testCase.expected)
  }

  struct UnsafeCase: Sendable, CustomTestStringConvertible {
    var context: DualPassRecognitionContext
    var lines: [RecognizedLine]
    var expected: AppleVisionDualPassDecisionReason
    var role: RecognitionRequestRole

    var testDescription: String { expected.rawValue }
  }

  private func unsafeCase(
    _ context: DualPassRecognitionContext,
    _ lines: [RecognizedLine],
    _ expected: AppleVisionDualPassDecisionReason,
    role: RecognitionRequestRole = .standard
  ) -> UnsafeCase {
    UnsafeCase(context: context, lines: lines, expected: expected, role: role)
  }

  private func decision(
    _ lines: [RecognizedLine],
    context: DualPassRecognitionContext = .isolatedCard,
    role: RecognitionRequestRole = .standard
  ) -> AppleVisionDualPassDecisionReason {
    ConditionalDualPassEvaluator.decision(
      lines: lines,
      context: context,
      requestRole: role,
      options: AppleVisionConditionalDualPassOptions(mode: .enabled)
    )
  }

  private func eligibleLines() -> [RecognizedLine] {
    [
      line("Morgan Vale", y: 0.82),
      line("morgan@cascade.example", y: 0.60),
      line("Mobile +1 202 555 0147", y: 0.38),
    ]
  }

  private func replacing(
    _ lines: [RecognizedLine], at index: Int, with replacement: RecognizedLine
  ) -> [RecognizedLine] {
    var result = lines
    result[index] = replacement
    return result
  }

  private func line(
    _ text: String,
    x: CGFloat = 0.08,
    y: CGFloat,
    width: CGFloat = 0.52,
    confidence: Float = 0.96,
    alternatives: [String] = []
  ) -> RecognizedLine {
    RecognizedLine(
      text: text,
      boundingBox: CGRect(x: x, y: y, width: width, height: 0.08),
      confidence: confidence,
      alternatives: alternatives
    )
  }
#else
  @Test("Conditional dual-pass tests require Apple Vision")
  func conditionalDualPassUnavailable() {}
#endif
