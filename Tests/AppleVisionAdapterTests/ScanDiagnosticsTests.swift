import AppleVisionBenchmarking
import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  final class DeterministicDiagnosticsClock: AppleVisionDiagnosticsClock, @unchecked Sendable {
    private let lock = NSLock()
    private var milliseconds: Double

    init(milliseconds: Double = 1_000) {
      self.milliseconds = milliseconds
    }

    func nowMilliseconds() -> Double {
      lock.lock()
      defer { lock.unlock() }
      return milliseconds
    }

    func advance(by amount: Double) {
      lock.lock()
      milliseconds += amount
      lock.unlock()
    }
  }

  @Test("Diagnostics are disabled by default and expose only aggregate state")
  func diagnosticsContractIsOptInAndRedacted() throws {
    let configuration = AppleVisionScanConfiguration()
    #expect(!configuration.diagnostics.isEnabled)

    let diagnostics = AppleVisionScanDiagnostics(
      stageTimings: [
        AppleVisionStageTiming(stage: .preprocessing, durationMilliseconds: 3),
        AppleVisionStageTiming(stage: .total, durationMilliseconds: 8),
      ],
      totalVisionRequestCount: 2,
      rectangleRequestCount: 0,
      saliencyRequestCount: 0,
      textRecognitionRequestCount: 2,
      primaryTextRecognitionRequestCount: 1,
      secondaryTextRecognitionRequestCount: 1,
      targetedReRecognitionRequestCount: 0,
      dualPassConfigured: true,
      dualPassExecuted: true,
      targetedReRecognitionConfigured: true,
      targetedReRecognitionExecuted: false,
      cardIsolationConfigured: false,
      cardIsolationAttempted: false,
      cardIsolationSucceeded: false,
      fullImageFallbackUsed: false
    )

    let allowedNames: Set<String> = [
      "schemaVersion", "stageTimings", "totalVisionRequestCount",
      "rectangleRequestCount", "saliencyRequestCount", "textRecognitionRequestCount",
      "primaryTextRecognitionRequestCount", "secondaryTextRecognitionRequestCount",
      "targetedReRecognitionRequestCount", "dualPassConfigured", "dualPassExecuted",
      "conditionalDualPassConfigured", "dualPassSkipCount", "dualPassDecisionCounts",
      "targetedReRecognitionConfigured", "targetedReRecognitionExecuted",
      "cardIsolationConfigured", "cardIsolationAttempted", "cardIsolationSucceeded",
      "fullImageFallbackUsed",
    ]
    let labels = Set(Mirror(reflecting: diagnostics).children.compactMap(\.label))
    #expect(labels == allowedNames)

    let encoded = try JSONEncoder().encode(diagnostics)
    let json = try #require(String(data: encoded, encoding: .utf8))
    #expect(!json.contains("example.net"))
    #expect(!json.contains("/" + "Users/"))
    #expect(!json.contains("token"))
    #expect(!json.contains("image"))
  }

  @Test("Injected clocks produce deterministic ordered stage reports")
  func deterministicStageReport() {
    let clock = DeterministicDiagnosticsClock()
    let instrumentation = ScanInstrumentation(clock: clock)

    instrumentation.measure(.preprocessing) {
      clock.advance(by: 4)
    }
    instrumentation.recordRectangleRequest()
    instrumentation.measure(.cardDetection) {
      clock.advance(by: 3)
    }
    instrumentation.recordTextRequest(secondary: false, targeted: false)
    instrumentation.measure(.primaryRecognition) {
      clock.advance(by: 9)
    }
    instrumentation.recordTextRequest(secondary: true, targeted: true)
    instrumentation.recordDualPassExecuted()
    instrumentation.recordDualPassDecision(.lowConfidence)
    clock.advance(by: 2)

    let configuration = AppleVisionScanConfiguration(
      cardRegion: AppleVisionCardRegionConfiguration(mode: .automatic),
      diagnostics: AppleVisionDiagnosticsOptions(isEnabled: true, clock: clock)
    )
    let report = instrumentation.snapshot(configuration: configuration)

    #expect(
      report.stageTimings.map(\.stage)
        == [.preprocessing, .cardDetection, .primaryRecognition, .total])
    #expect(report.stageTimings.map(\.durationMilliseconds) == [4, 3, 9, 18])
    #expect(report.totalVisionRequestCount == 3)
    #expect(report.textRecognitionRequestCount == 2)
    #expect(report.primaryTextRecognitionRequestCount == 1)
    #expect(report.secondaryTextRecognitionRequestCount == 1)
    #expect(report.targetedReRecognitionRequestCount == 1)
    #expect(report.dualPassExecuted)
    #expect(report.dualPassSkipCount == 0)
    #expect(
      report.dualPassDecisionCounts
        == [AppleVisionDualPassDecisionCount(reason: .lowConfidence, count: 1)])
    #expect(report.targetedReRecognitionExecuted)
  }

  @Test("Legacy diagnostics decode with conditional fields disabled")
  func legacyDiagnosticsDecode() throws {
    let legacy =
      #"{"schemaVersion":1,"stageTimings":[],"totalVisionRequestCount":2,"rectangleRequestCount":0,"saliencyRequestCount":0,"textRecognitionRequestCount":2,"primaryTextRecognitionRequestCount":1,"secondaryTextRecognitionRequestCount":1,"targetedReRecognitionRequestCount":0,"dualPassConfigured":true,"dualPassExecuted":true,"targetedReRecognitionConfigured":false,"targetedReRecognitionExecuted":false,"cardIsolationConfigured":false,"cardIsolationAttempted":false,"cardIsolationSucceeded":false,"fullImageFallbackUsed":false}"#
    let decoded = try JSONDecoder().decode(
      AppleVisionScanDiagnostics.self,
      from: try #require(legacy.data(using: .utf8))
    )

    #expect(decoded.schemaVersion == 1)
    #expect(!decoded.conditionalDualPassConfigured)
    #expect(decoded.dualPassSkipCount == 0)
    #expect(decoded.dualPassDecisionCounts.isEmpty)
  }

  @Test("Diagnostics ON and OFF preserve all golden field results")
  func diagnosticsPreserveGoldenResults() async throws {
    let scenes = try GoldenSceneManifest.load()
    #expect(scenes.count == 50)

    for scene in scenes {
      let image = try GoldenSceneRenderer.render(scene)
      let disabledScanner = AppleVisionScanner(configuration: scene.scanConfiguration)

      var enabledConfiguration = scene.scanConfiguration
      enabledConfiguration.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
      let enabledScanner = AppleVisionScanner(configuration: enabledConfiguration)

      let disabled = try await disabledScanner.scanAsync(cgImage: image)
      let enabled = try await enabledScanner.scanAsync(cgImage: image)

      #expect(disabled.diagnostics == nil)
      #expect(enabled.diagnostics != nil)
      #expect(disabled.tokens == enabled.tokens, "token parity failed for \(scene.identifier)")
      #expect(disabled.fields == enabled.fields, "field parity failed for \(scene.identifier)")
      #expect(
        disabled.cardRegionSelection == enabled.cardRegionSelection,
        "card-region parity failed for \(scene.identifier)"
      )

      let diagnostics = try #require(enabled.diagnostics)
      #expect(diagnostics.stageTimings.last?.stage == .total)
      #expect(diagnostics.stageTimings.map(\.stage).contains(.classification))
      #expect(
        diagnostics.totalVisionRequestCount
          == diagnostics.rectangleRequestCount + diagnostics.saliencyRequestCount
          + diagnostics.textRecognitionRequestCount
      )
      #expect(diagnostics.cardIsolationConfigured == !scene.resolvedCardRegionIsDisabled)
      #expect(diagnostics.cardIsolationAttempted == !scene.resolvedCardRegionIsDisabled)
      switch enabled.cardRegionSelection {
      case .disabled:
        #expect(!diagnostics.cardIsolationSucceeded)
        #expect(!diagnostics.fullImageFallbackUsed)
      case .isolated:
        #expect(diagnostics.cardIsolationSucceeded)
        #expect(!diagnostics.fullImageFallbackUsed)
      case .fullImageFallback:
        #expect(!diagnostics.cardIsolationSucceeded)
        #expect(diagnostics.fullImageFallbackUsed)
      }
    }
  }

  @Test("Token-only scans preserve parity and report dual-pass request counts")
  func tokenScanDiagnosticsParityAndCounts() async throws {
    let scene = try #require(
      GoldenSceneManifest.load().first {
        $0.layoutIdentifier == "golden-straight-card-en" && $0.variantIdentifier == "clean"
      }
    )
    let image = try GoldenSceneRenderer.render(scene)

    var disabledConfiguration = scene.scanConfiguration
    disabledConfiguration.cardRegion = AppleVisionCardRegionConfiguration(mode: .disabled)
    disabledConfiguration.performsTargetedReRecognition = false

    var enabledConfiguration = disabledConfiguration
    enabledConfiguration.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)

    let disabled = try await AppleVisionScanner(configuration: disabledConfiguration)
      .scanTokensAsync(cgImage: image)
    let enabled = try await AppleVisionScanner(configuration: enabledConfiguration)
      .scanTokensAsync(cgImage: image)

    #expect(disabled.tokens == enabled.tokens)
    #expect(disabled.cardRegionSelection == enabled.cardRegionSelection)
    #expect(disabled.diagnostics == nil)

    let diagnostics = try #require(enabled.diagnostics)
    #expect(diagnostics.rectangleRequestCount == 0)
    #expect(diagnostics.saliencyRequestCount == 0)
    #expect(diagnostics.primaryTextRecognitionRequestCount == 1)
    #expect(diagnostics.secondaryTextRecognitionRequestCount == 1)
    #expect(diagnostics.textRecognitionRequestCount == 2)
    #expect(diagnostics.totalVisionRequestCount == 2)
    #expect(diagnostics.dualPassConfigured)
    #expect(diagnostics.dualPassExecuted)
    #expect(!diagnostics.targetedReRecognitionConfigured)
    #expect(!diagnostics.targetedReRecognitionExecuted)
    #expect(!diagnostics.stageTimings.map(\.stage).contains(.classification))
  }
#else
  @Test("Scan diagnostics tests require Apple Vision")
  func scanDiagnosticsUnavailable() {}
#endif
