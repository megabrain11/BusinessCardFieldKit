import Foundation
import Testing

@testable import AppleVisionAdapter
@testable import AppleVisionBenchmarking

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics

  @Test("Projective barcode mapping preserves normalized source geometry")
  func projectiveMappingUsesAllFourCorners() {
    let card = BarcodeMaskQuadrilateral(
      topLeft: CGPoint(x: 0.20, y: 0.82),
      topRight: CGPoint(x: 0.84, y: 0.70),
      bottomLeft: CGPoint(x: 0.26, y: 0.16),
      bottomRight: CGPoint(x: 0.78, y: 0.08)
    )
    let barcode = BarcodeMaskQuadrilateral(
      topLeft: CGPoint(x: 0.48, y: 0.57),
      topRight: CGPoint(x: 0.66, y: 0.54),
      bottomLeft: CGPoint(x: 0.49, y: 0.38),
      bottomRight: CGPoint(x: 0.65, y: 0.36)
    )

    let regions = ProjectiveBarcodeMaskMapper.regions(barcodes: [barcode], card: card)
    #expect(regions?.count == 1)
    guard let region = regions?.first else { return }
    #expect(region.x > 0.35 && region.x < 0.50)
    #expect(region.y > 0.30 && region.y < 0.45)
    #expect(region.width > 0.20 && region.width < 0.35)
    #expect(region.height > 0.20 && region.height < 0.40)
  }

  @Test("Degenerate or invalid quadrilaterals fail closed")
  func projectiveMappingFailsClosed() {
    let degenerate = BarcodeMaskQuadrilateral(
      topLeft: CGPoint(x: 0.2, y: 0.2),
      topRight: CGPoint(x: 0.2, y: 0.2),
      bottomLeft: CGPoint(x: 0.2, y: 0.2),
      bottomRight: CGPoint(x: 0.2, y: 0.2)
    )
    let barcode = BarcodeMaskQuadrilateral(
      topLeft: CGPoint(x: 0.3, y: 0.7),
      topRight: CGPoint(x: 0.4, y: 0.7),
      bottomLeft: CGPoint(x: 0.3, y: 0.6),
      bottomRight: CGPoint(x: 0.4, y: 0.6)
    )
    #expect(ProjectiveBarcodeMaskMapper.regions(barcodes: [barcode], card: degenerate) == nil)

    let outside = BarcodeMaskQuadrilateral(
      topLeft: CGPoint(x: -0.5, y: 1.5),
      topRight: CGPoint(x: -0.4, y: 1.5),
      bottomLeft: CGPoint(x: -0.5, y: 1.4),
      bottomRight: CGPoint(x: -0.4, y: 1.4)
    )
    let regularCard = BarcodeMaskQuadrilateral(
      topLeft: CGPoint(x: 0, y: 1),
      topRight: CGPoint(x: 1, y: 1),
      bottomLeft: CGPoint(x: 0, y: 0),
      bottomRight: CGPoint(x: 1, y: 0)
    )
    #expect(ProjectiveBarcodeMaskMapper.regions(barcodes: [outside], card: regularCard) == nil)
  }

  @Test("Rectified barcode masking remains the default strategy")
  func defaultMaskingStrategyRemainsShippedPath() {
    #expect(AppleVisionScanConfiguration().barcodeMaskingStrategy == .rectifiedRedetection)
    #expect(
      AppleVisionScanConfiguration(
        barcodeMaskingStrategy: .projectiveSourceObservation
      ).barcodeMaskingStrategy == .projectiveSourceObservation
    )
  }

  @Test("Projective masking preserves all fourteen card-back results")
  func projectiveStrategyPreservesCardBackResults() throws {
    let manifest = try cardBackManifest()
    for record in manifest.cases {
      let image = try CardBackSceneRenderer.render(record)
      let attemptsIsolation = record.attemptsCardIsolation ?? false
      let baselineConfiguration = CardBackBenchmarkRunner.scanConfiguration(
        attemptsCardIsolation: attemptsIsolation,
        maskingStrategy: .rectifiedRedetection
      )
      let projectiveConfiguration = CardBackBenchmarkRunner.scanConfiguration(
        attemptsCardIsolation: attemptsIsolation,
        maskingStrategy: .projectiveSourceObservation
      )
      var baseline = baselineConfiguration
      baseline.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
      var projective = projectiveConfiguration
      projective.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
      let expected = try CardBackScanner(configuration: baseline).scan(cgImage: image)
      let experimental = try CardBackScanner(configuration: projective).scan(cgImage: image)

      #expect(experimental.tokens == expected.tokens)
      #expect(experimental.fields == expected.fields)
      #expect(experimental.detectedBarcodes == expected.detectedBarcodes)
      #expect(experimental.cardRegionSelection == expected.cardRegionSelection)
      let diagnostics = try #require(experimental.diagnostics)
      #expect(
        diagnostics.maskingStrategy == AppleVisionBarcodeMaskingStrategy.projectiveSourceObservation
      )
      if attemptsIsolation, case .isolated = experimental.cardRegionSelection {
        #expect(diagnostics.projectiveMaskingApplied)
        #expect(diagnostics.projectiveMaskFallbackCount == 0)
        #expect(diagnostics.isolatedMaskBarcodeRequestCount == 0)
        #expect(experimental.diagnostics?.totalBarcodeRequestCount == 1)
      }
    }
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
  @Test("Projective barcode masking requires Apple Vision")
  func projectiveBarcodeMaskingUnavailable() {}
#endif
