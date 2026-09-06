import Foundation
import Testing

@testable import AppleVisionAdapter
@testable import AppleVisionBenchmarking

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  @Test("Card-back diagnostics are opt-in and content-free")
  func cardBackDiagnosticsContract() throws {
    #expect(!AppleVisionScanConfiguration().diagnostics.isEnabled)
    let diagnostics = AppleVisionBackScanDiagnostics(
      stageTimings: [
        AppleVisionBackStageTiming(stage: .sourceBarcodeDetection, durationMilliseconds: 2),
        AppleVisionBackStageTiming(stage: .total, durationMilliseconds: 7),
      ],
      totalBarcodeRequestCount: 2,
      sourceBarcodeRequestCount: 1,
      isolatedMaskBarcodeRequestCount: 1,
      isolatedMaskDetectionExecuted: true
    )
    let allowedNames: Set<String> = [
      "schemaVersion", "stageTimings", "totalBarcodeRequestCount",
      "sourceBarcodeRequestCount", "sourceBarcodeRecoveryRequestCount",
      "sourceBarcodeRecoveryExecuted", "isolatedMaskBarcodeRequestCount",
      "isolatedMaskDetectionExecuted", "maskingStrategy", "projectiveMaskingApplied",
      "projectiveMaskFallbackCount",
    ]
    #expect(Set(Mirror(reflecting: diagnostics).children.compactMap(\.label)) == allowedNames)

    let json = try #require(
      String(data: JSONEncoder().encode(diagnostics), encoding: .utf8)
    )
    for forbidden in [
      "BEGIN:VCARD", "example.net", "payload", "boundingBox", "ocrText",
      "tokenValue", "imagePath", "/" + "Users/",
    ] {
      #expect(!json.localizedCaseInsensitiveContains(forbidden))
    }
  }

  @Test("Legacy card-back diagnostics decode with projective fields disabled")
  func legacyCardBackDiagnosticsDecode() throws {
    let legacy =
      #"{"schemaVersion":1,"stageTimings":[],"totalBarcodeRequestCount":1,"sourceBarcodeRequestCount":1,"isolatedMaskBarcodeRequestCount":0,"isolatedMaskDetectionExecuted":false}"#
    let decoded = try JSONDecoder().decode(
      AppleVisionBackScanDiagnostics.self,
      from: Data(legacy.utf8)
    )
    #expect(decoded.maskingStrategy == .rectifiedRedetection)
    #expect(!decoded.projectiveMaskingApplied)
    #expect(decoded.projectiveMaskFallbackCount == 0)
    #expect(decoded.sourceBarcodeRecoveryRequestCount == 0)
    #expect(!decoded.sourceBarcodeRecoveryExecuted)
  }

  @Test("Injected clock produces deterministic back-stage timings and request counts")
  func deterministicCardBackDiagnostics() {
    let clock = DeterministicDiagnosticsClock()
    let instrumentation = BackScanInstrumentation(clock: clock)
    instrumentation.recordSourceBarcodeRequest()
    instrumentation.recordSourceBarcodeRecoveryRequest()
    instrumentation.measure(.sourceBarcodeDetection) { clock.advance(by: 3) }
    instrumentation.measure(.tokenRecognition) { clock.advance(by: 5) }
    instrumentation.recordIsolatedMaskBarcodeRequest()
    instrumentation.measure(.isolatedMaskDetection) { clock.advance(by: 2) }
    instrumentation.measure(.classificationAndMerge) { clock.advance(by: 1) }
    clock.advance(by: 1)

    let diagnostics = instrumentation.snapshot()
    #expect(
      diagnostics.stageTimings.map(\.stage)
        == [
          .sourceBarcodeDetection, .tokenRecognition, .isolatedMaskDetection,
          .classificationAndMerge, .total,
        ]
    )
    #expect(diagnostics.stageTimings.map(\.durationMilliseconds) == [3, 5, 2, 1, 12])
    #expect(diagnostics.totalBarcodeRequestCount == 3)
    #expect(diagnostics.sourceBarcodeRequestCount == 2)
    #expect(diagnostics.sourceBarcodeRecoveryRequestCount == 1)
    #expect(diagnostics.sourceBarcodeRecoveryExecuted)
    #expect(diagnostics.isolatedMaskBarcodeRequestCount == 1)
    #expect(diagnostics.isolatedMaskDetectionExecuted)
  }

  @Test("Diagnostics ON and OFF preserve every synthetic card-back result")
  func cardBackDiagnosticsParity() throws {
    let manifest = try cardBackDiagnosticsManifest()
    for record in manifest.cases {
      let image = try CardBackSceneRenderer.render(record)
      let attemptsIsolation = record.attemptsCardIsolation ?? false
      let base = CardBackBenchmarkRunner.scanConfiguration(
        attemptsCardIsolation: attemptsIsolation
      )
      let disabled = try CardBackScanner(configuration: base).scan(cgImage: image)
      var enabledConfiguration = base
      enabledConfiguration.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
      let enabled = try CardBackScanner(configuration: enabledConfiguration).scan(cgImage: image)

      #expect(disabled.diagnostics == nil)
      #expect(enabled.diagnostics != nil)
      #expect(disabled.tokens == enabled.tokens)
      #expect(disabled.fields == enabled.fields)
      #expect(disabled.detectedBarcodes == enabled.detectedBarcodes)
      #expect(disabled.cardRegionSelection == enabled.cardRegionSelection)
      let diagnostics = try #require(enabled.diagnostics)
      #expect(diagnostics.sourceBarcodeRequestCount == 1)
      #expect(
        diagnostics.isolatedMaskBarcodeRequestCount
          == (attemptsIsolation ? 1 : 0)
      )
    }
  }

  @Test("Disabled fallback and isolated paths report bounded barcode requests")
  func cardBackDiagnosticsPathCounts() throws {
    let manifest = try cardBackDiagnosticsManifest()
    let textRecord = try #require(
      manifest.cases.first { $0.identifier == "back-qr-with-text" }
    )
    let isolatedRecord = try #require(
      manifest.cases.first {
        $0.identifier == "back-isolated-perspective-nearby-text"
      }
    )

    let disabled = try diagnosticScan(textRecord, attemptsIsolation: false)
    #expect(disabled.cardRegionSelection == .disabled)
    #expect(disabled.diagnostics?.totalBarcodeRequestCount == 1)
    #expect(disabled.diagnostics?.isolatedMaskBarcodeRequestCount == 0)

    let fallback = try diagnosticScan(
      textRecord,
      attemptsIsolation: true,
      forcesFallback: true
    )
    #expect(fallback.cardRegionSelection == .fullImageFallback)
    #expect(fallback.diagnostics?.totalBarcodeRequestCount == 1)
    #expect(fallback.diagnostics?.isolatedMaskBarcodeRequestCount == 0)

    let isolated = try diagnosticScan(isolatedRecord, attemptsIsolation: true)
    guard case .isolated = isolated.cardRegionSelection else {
      Issue.record("Expected isolated diagnostic path")
      return
    }
    #expect(isolated.diagnostics?.totalBarcodeRequestCount == 2)
    #expect(isolated.diagnostics?.isolatedMaskBarcodeRequestCount == 1)
  }

  private func diagnosticScan(
    _ record: CardBackCorpusCase,
    attemptsIsolation: Bool,
    forcesFallback: Bool = false
  ) throws -> AppleVisionBackScanResult {
    var configuration = CardBackBenchmarkRunner.scanConfiguration(
      attemptsCardIsolation: attemptsIsolation
    )
    if forcesFallback {
      configuration.cardRegion = AppleVisionCardRegionConfiguration(
        mode: .automatic,
        minimumTextEvidenceScore: 1
      )
    }
    configuration.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
    return try CardBackScanner(configuration: configuration).scan(
      cgImage: CardBackSceneRenderer.render(record)
    )
  }

  private func cardBackDiagnosticsManifest() throws -> CardBackCorpusManifest {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try CardBackCorpusManifest(
      data: Data(contentsOf: root.appendingPathComponent("Fixtures/CardBack/manifest.json"))
    )
  }
#else
  @Test("Card-back diagnostics require Apple Vision")
  func cardBackDiagnosticsUnavailable() {}
#endif
