import AppleVisionAdapter
import Foundation
import Testing

@testable import AppleVisionBenchmarking

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  @Test("Golden corpus expands to two deterministic variants for 25 layouts")
  func goldenCorpusCoverageAndDeterminism() throws {
    let manifest = try GoldenSceneManifest.manifest()
    let scenes = try manifest.expandedCases()

    #expect(manifest.schemaVersion == 2)
    #expect(manifest.layouts.count == 25)
    #expect(scenes.count == 50)
    #expect(
      Dictionary(grouping: scenes, by: \.layoutIdentifier).values.allSatisfy {
        $0.count == 2
      })
    #expect(Set(scenes.map(\.identifier)).count == scenes.count)

    let requiredTags: Set<String> = [
      "automatic-isolation", "blur", "complex-background", "crop", "dark-card",
      "exposure", "glare", "hangul", "low-contrast", "overlapping-card",
      "perspective-15", "perspective-30", "portrait", "qr", "shadow", "small-text",
      "two-column",
    ]
    #expect(requiredTags.isSubset(of: Set(scenes.flatMap(\.tags))))

    let scene = try #require(scenes.first)
    let first = try GoldenSceneRenderer.render(scene)
    let second = try GoldenSceneRenderer.render(scene)
    #expect(first.width == second.width)
    #expect(first.height == second.height)
    #expect(first.dataProvider?.data as Data? == second.dataProvider?.data as Data?)
  }

  @Test("Aggregate benchmark reports are independent of sample order")
  func aggregateReportIsOrderIndependent() {
    let samples = [
      sample(total: 24, primary: 1, secondary: 1, targeted: 0, mismatch: 0),
      sample(total: 12, primary: 1, secondary: 0, targeted: 0, mismatch: 1),
      sample(total: 36, primary: 1, secondary: 1, targeted: 1, mismatch: 0),
    ]
    let forward = DiagnosticsBenchmarkAggregator.aggregate(
      configuration: .shippedDefault, samples: samples)
    let reverse = DiagnosticsBenchmarkAggregator.aggregate(
      configuration: .shippedDefault, samples: Array(samples.reversed()))

    #expect(forward == reverse)
    #expect(forward.totalDurationMilliseconds.p50 == 24)
    #expect(forward.totalDurationMilliseconds.p95 == 36)
    #expect(forward.fieldExactRate == 2.0 / 3.0)
  }

  @Test("Benchmark report contract remains aggregate-only and redacted")
  func benchmarkReportIsAggregateOnly() throws {
    let report = DiagnosticsBenchmarkReport(
      corpusVersion: "synthetic-1",
      layoutCount: 25,
      caseCount: 50,
      warmupRuns: 1,
      measuredRuns: 2,
      tagCoverage: ["blur": 4],
      configurations: [
        DiagnosticsBenchmarkAggregator.aggregate(
          configuration: .shippedDefault,
          samples: [sample(total: 10, primary: 1, secondary: 1, targeted: 0, mismatch: 0)]
        )
      ]
    )

    let forbiddenLabels: Set<String> = [
      "caseIdentifier", "confidence", "image", "imagePath", "ocrText", "path", "token",
    ]
    #expect(
      forbiddenLabels.isDisjoint(with: Set(Mirror(reflecting: report).children.compactMap(\.label)))
    )

    let data = try JSONEncoder().encode(report)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(!json.localizedCaseInsensitiveContains("casey.rowan"))
    #expect(!json.localizedCaseInsensitiveContains("northstar.example"))
    #expect(!json.contains("/" + "Users/"))
    #expect(!json.localizedCaseInsensitiveContains("ocrText"))
    #expect(!json.localizedCaseInsensitiveContains("confidence"))
    #expect(!json.localizedCaseInsensitiveContains("imagePath"))
  }

  @Test("Benchmark configurations alter only their named OCR toggles")
  func benchmarkConfigurationsAreMinimal() {
    for benchmark in DiagnosticsBenchmarkConfiguration.allCases {
      var configuration = AppleVisionScanConfiguration()
      let original = configuration
      benchmark.apply(to: &configuration)

      #expect(configuration.preprocessing == original.preprocessing)
      #expect(configuration.infersTokenLanguages == original.infersTokenLanguages)
      #expect(configuration.cardRegion == original.cardRegion)
      switch benchmark {
      case .shippedDefault:
        #expect(configuration.dualPassRecognition == original.dualPassRecognition)
        #expect(
          configuration.performsTargetedReRecognition
            == original.performsTargetedReRecognition)
        #expect(configuration.conditionalDualPass == original.conditionalDualPass)
      case .conditionalDualPass:
        #expect(configuration.dualPassRecognition == original.dualPassRecognition)
        #expect(configuration.conditionalDualPass.mode == .enabled)
        #expect(
          configuration.performsTargetedReRecognition
            == original.performsTargetedReRecognition)
      case .noDualPass:
        #expect(!configuration.dualPassRecognition)
        #expect(
          configuration.performsTargetedReRecognition
            == original.performsTargetedReRecognition)
        #expect(configuration.conditionalDualPass == original.conditionalDualPass)
      case .noTargetedReRecognition:
        #expect(configuration.dualPassRecognition == original.dualPassRecognition)
        #expect(!configuration.performsTargetedReRecognition)
        #expect(configuration.conditionalDualPass == original.conditionalDualPass)
      case .singlePassWithoutTargetedReRecognition:
        #expect(!configuration.dualPassRecognition)
        #expect(!configuration.performsTargetedReRecognition)
        #expect(configuration.conditionalDualPass == original.conditionalDualPass)
      }
    }
  }

  @Test("Conditional comparison is paired and input-order stable")
  func conditionalComparisonIsPaired() throws {
    let baseline = [
      sample(total: 20, primary: 1, secondary: 1, targeted: 0, mismatch: 0),
      sample(total: 30, primary: 1, secondary: 1, targeted: 0, mismatch: 1),
    ]
    let experiment = [
      sample(total: 12, primary: 1, secondary: 0, targeted: 0, mismatch: 0),
      sample(total: 18, primary: 1, secondary: 0, targeted: 0, mismatch: 0),
    ]
    let comparison = try #require(
      DiagnosticsBenchmarkAggregator.conditionalComparison(
        baseline: baseline, experiment: experiment))

    #expect(comparison.sampleCount == 2)
    #expect(comparison.improvedExactCaseCount == 1)
    #expect(comparison.regressedExactCaseCount == 0)
    #expect(comparison.secondaryRequestP50Delta == -1)
    #expect(comparison.secondaryRequestP95Delta == -1)
    #expect(comparison.secondaryRequestTotalDelta == -2)
  }

  private func sample(
    total: Double,
    primary: Int,
    secondary: Int,
    targeted: Int,
    mismatch: Int
  ) -> DiagnosticsBenchmarkSample {
    DiagnosticsBenchmarkSample(
      diagnostics: AppleVisionScanDiagnostics(
        stageTimings: [
          AppleVisionStageTiming(stage: .primaryRecognition, durationMilliseconds: total / 2),
          AppleVisionStageTiming(stage: .total, durationMilliseconds: total),
        ],
        totalVisionRequestCount: primary + secondary + targeted,
        rectangleRequestCount: 0,
        saliencyRequestCount: 0,
        textRecognitionRequestCount: primary + secondary + targeted,
        primaryTextRecognitionRequestCount: primary,
        secondaryTextRecognitionRequestCount: secondary,
        targetedReRecognitionRequestCount: targeted,
        dualPassConfigured: secondary > 0,
        dualPassExecuted: secondary > 0,
        targetedReRecognitionConfigured: targeted > 0,
        targetedReRecognitionExecuted: targeted > 0,
        cardIsolationConfigured: false,
        cardIsolationAttempted: false,
        cardIsolationSucceeded: false,
        fullImageFallbackUsed: false
      ),
      mismatchedFieldCount: mismatch,
      reviewRecommended: mismatch > 0
    )
  }
#else
  @Test("Diagnostics benchmark tests require Apple Vision")
  func diagnosticsBenchmarkUnavailable() {}
#endif
