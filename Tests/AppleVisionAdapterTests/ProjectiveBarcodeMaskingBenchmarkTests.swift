import Foundation
import Testing

@testable import AppleVisionBenchmarking

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  @Test("Paired masking benchmark reports isolated request reduction")
  func projectiveStrategyBenchmark() throws {
    let comparison = try CardBackMaskingStrategyBenchmarkRunner(
      warmupRuns: 0,
      measuredRuns: 1
    ).run(manifest: cardBackManifest())
    #expect(comparison.caseCount == 14)
    #expect(comparison.resultParityRate == 1)
    #expect(comparison.tokenParityRate == 1)
    #expect(comparison.fieldParityRate == 1)
    #expect(comparison.barcodeParityRate == 1)
    #expect(comparison.cardRegionParityRate == 1)
    #expect(comparison.isolatedSampleCount == 2)
    #expect(comparison.projectiveMaskingAppliedSampleCount == 2)
    #expect(comparison.projectiveMaskFallbackCount == 0)
    #expect(comparison.isolatedBarcodeRequestReduction.p50 == 1)
    #expect(comparison.isolatedBarcodeRequestReduction.p95 == 1)
    #expect(comparison.isolatedDurationDeltaMilliseconds.sampleCount == 2)
  }

  private func cardBackManifest() throws -> CardBackCorpusManifest {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try CardBackCorpusManifest(
      data: Data(contentsOf: root.appendingPathComponent("Fixtures/CardBack/manifest.json"))
    )
  }
#else
  @Test("Projective barcode masking benchmark requires Apple Vision")
  func projectiveBarcodeMaskingBenchmarkUnavailable() {}
#endif
