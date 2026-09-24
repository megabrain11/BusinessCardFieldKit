import Foundation
import Testing

@testable import AppleVisionAdapter
@testable import AppleVisionBenchmarking

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  @Test("Barcode recovery is disabled by default and clamps its bounds")
  func barcodeRecoveryConfiguration() {
    let defaults = AppleVisionScanConfiguration().barcodeDetectionRecovery
    #expect(!defaults.isEnabled)

    let clamped = AppleVisionBarcodeDetectionRecoveryOptions(
      isEnabled: true,
      minimumLongEdge: 12_000,
      maximumLongEdge: 100,
      contrastAdjustment: 5,
      sharpeningIntensity: -1
    )
    #expect(clamped.minimumLongEdge == 8_192)
    #expect(clamped.maximumLongEdge == 8_192)
    #expect(clamped.contrastAdjustment == 1)
    #expect(clamped.sharpeningIntensity == 0)
  }

  @Test("Recovery preprocessing is deterministic and preserves normalized geometry")
  func barcodeRecoveryPreprocessing() throws {
    let record = try #require(stressManifest().cases.first)
    let source = try CardBackSceneRenderer.render(record)
    let options = AppleVisionBarcodeDetectionRecoveryOptions(isEnabled: true)
    let first = try #require(
      BarcodeDetectionRecoveryPreprocessor.preprocess(source, options: options)
    )
    let second = try #require(
      BarcodeDetectionRecoveryPreprocessor.preprocess(source, options: options)
    )

    #expect(first.width == 3_200)
    #expect(first.height == 2_134)
    #expect(first.width == second.width)
    #expect(first.height == second.height)
    #expect(first.dataProvider?.data == second.dataProvider?.data)
  }

  @Test("Successful first barcode request never pays the recovery request")
  func barcodeRecoveryShortCircuits() throws {
    let record = try #require(
      stressManifest().cases.first { $0.tags.contains("small") }
    )
    let image = try CardBackSceneRenderer.render(record)
    let runner = CardBackBenchmarkRunner(warmupRuns: 0, measuredRuns: 1)
    let baseline = try runner.scanResult(record, image: image)
    let experimental = try runner.scanResult(
      record,
      image: image,
      barcodeDetectionRecovery: AppleVisionBarcodeDetectionRecoveryOptions(isEnabled: true)
    )

    #expect(baseline.result.detectedBarcodes == experimental.result.detectedBarcodes)
    #expect(baseline.result.fields == experimental.result.fields)
    #expect(experimental.result.diagnostics?.sourceBarcodeRequestCount == 1)
    #expect(experimental.result.diagnostics?.sourceBarcodeRecoveryRequestCount == 0)
    #expect(experimental.result.diagnostics?.sourceBarcodeRecoveryExecuted == false)
  }

  @Test("Paired stress evidence recovers a barcode without regressions")
  func barcodeRecoveryPairedEvidence() throws {
    let comparison = try BarcodeDetectionRecoveryBenchmarkRunner(
      warmupRuns: 0,
      measuredRuns: 1
    ).run(manifest: stressManifest())

    #expect(comparison.caseCount == 18)
    #expect(comparison.experimentalBarcodeExactRate > comparison.baselineBarcodeExactRate)
    #expect(comparison.recoveredSampleCount > 0)
    #expect(comparison.regressedSampleCount == 0)
    #expect(comparison.fieldRegressionSampleCount == 0)
    #expect(comparison.baselineBarcodeExactPreservationRate == 1)
    #expect(comparison.tokenParityRate == 1)
    #expect(comparison.cardRegionParityRate == 1)
    #expect(comparison.recoveryExecutedSampleCount == 6)
    #expect(comparison.baselineSourceBarcodeRequests.p95 == 1)
    #expect(comparison.experimentalSourceBarcodeRequests.p95 == 2)
    #expect(
      comparison.styleSummaries.first { $0.style == "dot-style" }?
        .recoveredSampleCount == 1
    )

    let encoded = try JSONEncoder().encode(comparison)
    let report = try #require(String(data: encoded, encoding: .utf8)).lowercased()
    #expect(comparison.reportSchemaVersion == 1)
    for forbidden in [
      "identifier", "payload", "detectedbarcodes", "tokens", "ocr", "imagepath",
      "/users/", "example.net", "qr01", "stress@example",
    ] {
      #expect(!report.contains(forbidden))
    }
  }

  @Test("Barcode stress manifest contains only fictional contact values")
  func barcodeRecoveryManifestHygiene() throws {
    let data = try stressManifestData()
    let text = try #require(String(data: data, encoding: .utf8)).lowercased()
    #expect(!text.contains("/" + "users/"))
    for domain in ["gmail.com", "naver.com", "kakao.com", "outlook.com"] {
      #expect(!text.contains(domain))
    }
    #expect(text.contains("example.net"))
  }

  private func stressManifest() throws -> CardBackCorpusManifest {
    try CardBackCorpusManifest(data: stressManifestData())
  }

  private func stressManifestData() throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try Data(
      contentsOf: root.appendingPathComponent("Fixtures/BarcodeDetectionStress/manifest.json")
    )
  }
#else
  @Test("Barcode recovery requires Apple Vision")
  func barcodeRecoveryUnavailable() {}
#endif
