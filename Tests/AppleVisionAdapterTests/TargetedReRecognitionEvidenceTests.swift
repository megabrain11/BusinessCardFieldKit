import AppleVisionAdapter
import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionBenchmarking

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  @Test("Targeted stress corpus is versioned, deterministic, and fictional")
  func targetedStressCorpusHygiene() throws {
    let manifest = try TargetedStressManifest.manifest()
    let scenes = try manifest.expandedCases()

    #expect(manifest.corpusVersion == "targeted-rerecognition-stress-1.0.0")
    #expect(manifest.layouts.count == 12)
    #expect(scenes.count == 24)
    #expect(
      Dictionary(grouping: scenes, by: \.layoutIdentifier).values.allSatisfy {
        $0.count == 2
      })
    #expect(Set(scenes.map(\.identifier)).count == scenes.count)
    #expect(scenes.filter { $0.tags.contains("calibrated-threshold") }.count == 18)
    #expect(scenes.filter { $0.tags.contains("default-threshold") }.count == 4)
    #expect(scenes.filter { $0.tags.contains("nonexecution-control") }.count == 2)

    let requiredTags: Set<String> = [
      "automatic-isolation", "contact-blur", "contact-glare", "contact-shadow",
      "default-threshold", "email-stress", "expected-fallback", "low-contrast",
      "mixed-script", "nonexecution-control", "phone-stress", "small-contact",
      "url-stress",
    ]
    #expect(requiredTags.isSubset(of: Set(scenes.flatMap(\.tags))))

    for scene in scenes {
      let emails = scene.expected[CardField.emailAddresses.rawValue] ?? []
      let websites = scene.expected[CardField.websites.rawValue] ?? []
      let phones =
        (scene.expected[CardField.workPhoneNumbers.rawValue] ?? [])
        + (scene.expected[CardField.mobilePhoneNumbers.rawValue] ?? [])
      #expect(emails.allSatisfy { $0.hasSuffix(".example") })
      #expect(websites.allSatisfy { $0.hasSuffix(".example") })
      #expect(
        phones.allSatisfy {
          let digits = $0.filter(\.isNumber)
          return digits.contains("555") || digits.hasPrefix("010")
        }
      )
    }

    let scene = try #require(scenes.first)
    let first = try GoldenSceneRenderer.render(scene)
    let second = try GoldenSceneRenderer.render(scene)
    #expect(first.dataProvider?.data as Data? == second.dataProvider?.data as Data?)
  }

  @Test("Targeted aggregate comparison is independent of pair order")
  func targetedAggregationIsOrderIndependent() {
    let first = TargetedPairedSample(
      enabled: targetedSample(total: 30, targeted: 1, mismatches: []),
      disabled: targetedSample(total: 15, targeted: 0, mismatches: ["emailAddresses"])
    )
    let second = TargetedPairedSample(
      enabled: targetedSample(total: 40, targeted: 1, mismatches: ["websites"]),
      disabled: targetedSample(total: 20, targeted: 0, mismatches: [])
    )
    let pairs = [first, second]

    #expect(
      TargetedBenchmarkAggregator.pairedSummary(pairs)
        == TargetedBenchmarkAggregator.pairedSummary(Array(pairs.reversed())))
    #expect(TargetedBenchmarkAggregator.pairedSummary(pairs).recoveredFieldCount == 1)
    #expect(TargetedBenchmarkAggregator.pairedSummary(pairs).regressedFieldCount == 1)

    let forward = TargetedBenchmarkAggregator.configurationReport(
      configuration: .enabled, samples: pairs.map(\.enabled))
    let reverse = TargetedBenchmarkAggregator.configurationReport(
      configuration: .enabled, samples: pairs.reversed().map(\.enabled))
    #expect(forward == reverse)
  }

  @Test("Targeted benchmark report remains aggregate-only")
  func targetedReportIsRedacted() throws {
    let sample = targetedSample(total: 30, targeted: 1, mismatches: [])
    let report = TargetedReRecognitionBenchmarkReport(
      corpusVersion: "stress-1",
      layoutCount: 12,
      caseCount: 24,
      warmupRuns: 1,
      measuredRuns: 2,
      defaultThresholdCaseCount: 4,
      calibratedThresholdCaseCount: 18,
      nonExecutionControlCaseCount: 2,
      configurations: [
        TargetedBenchmarkAggregator.configurationReport(
          configuration: .enabled, samples: [sample])
      ],
      pairedComparison: TargetedPairSummary(
        recoveredFieldCount: 0,
        regressedFieldCount: 0,
        newReviewRecommendedCount: 0,
        resolvedReviewRecommendedCount: 0
      )
    )

    let data = try JSONEncoder().encode(report)
    let json = try #require(String(data: data, encoding: .utf8))
    for forbidden in [
      "morgan@", "harbor.example", "caseIdentifier", "ocrText", "confidence",
      "imagePath", "/" + "Users/",
    ] {
      #expect(!json.localizedCaseInsensitiveContains(forbidden))
    }
  }

  @Test("Stress scans preserve diagnostics parity and exercise both region paths")
  func targetedStressDiagnosticsParity() throws {
    let scenes = try TargetedStressManifest.load()
    var targetedExecutions = 0
    var calibratedExecutions = 0
    var isolatedCount = 0
    var fallbackCount = 0

    for scene in scenes {
      let image = try GoldenSceneRenderer.render(scene)
      var disabledDiagnosticsConfiguration = scene.scanConfiguration
      disabledDiagnosticsConfiguration.diagnostics = .disabled
      let withoutDiagnostics = try AppleVisionScanner(
        configuration: disabledDiagnosticsConfiguration
      ).scan(cgImage: image)

      var enabledDiagnosticsConfiguration = scene.scanConfiguration
      enabledDiagnosticsConfiguration.diagnostics = AppleVisionDiagnosticsOptions(
        isEnabled: true)
      let withDiagnostics = try AppleVisionScanner(
        configuration: enabledDiagnosticsConfiguration
      ).scan(cgImage: image)

      #expect(withoutDiagnostics.tokens == withDiagnostics.tokens)
      #expect(withoutDiagnostics.fields == withDiagnostics.fields)
      #expect(withoutDiagnostics.cardRegionSelection == withDiagnostics.cardRegionSelection)

      let diagnostics = try #require(withDiagnostics.diagnostics)
      if diagnostics.targetedReRecognitionExecuted { targetedExecutions += 1 }
      if scene.tags.contains("calibrated-threshold"),
        diagnostics.targetedReRecognitionExecuted
      {
        calibratedExecutions += 1
      }
      if scene.tags.contains("nonexecution-control") {
        #expect(!diagnostics.targetedReRecognitionExecuted)
      }
      switch withDiagnostics.cardRegionSelection {
      case .isolated:
        isolatedCount += 1
      case .fullImageFallback:
        fallbackCount += 1
      case .disabled:
        break
      }
    }

    #expect(targetedExecutions > 0)
    #expect(calibratedExecutions == 18)
    #expect(isolatedCount > 0)
    #expect(fallbackCount > 0)
  }

  @Test("Targeted benchmark measures enabled and disabled paths without policy changes")
  func targetedBenchmarkRunsBothPaths() throws {
    let report = try TargetedReRecognitionBenchmarkRunner(
      warmupRuns: 0,
      measuredRuns: 1
    ).run(manifest: TargetedStressManifest.manifest())

    #expect(report.layoutCount == 12)
    #expect(report.caseCount == 24)
    let enabled = try #require(
      report.configurations.first { $0.configuration == .enabled })
    let disabled = try #require(
      report.configurations.first { $0.configuration == .disabled })
    #expect(enabled.targetedExecutionRate > 0)
    #expect(enabled.exactCaseCount == 24)
    #expect(enabled.falseClearCount == 0)
    #expect(enabled.targetedRequestCount.p50 > 0)
    #expect(enabled.targetedDurationMilliseconds != nil)
    #expect(disabled.targetedExecutionRate == 0)
    #expect(disabled.exactCaseCount == 24)
    #expect(disabled.falseClearCount == 0)
    #expect(disabled.targetedRequestCount.p95 == 0)
    #expect(disabled.targetedDurationMilliseconds == nil)
    #expect(enabled.fieldSummaries.map(\.field) == CardField.allCases.map(\.rawValue))
  }

  @Test("Conditional dual-pass preserves all targeted stress fields")
  func conditionalDualPassTargetedStressParity() throws {
    let scenes = try TargetedStressManifest.load()
    var failures: [String] = []
    for scene in scenes {
      let image = try GoldenSceneRenderer.render(scene)
      let baseline = try AppleVisionScanner(configuration: scene.scanConfiguration)
        .scan(cgImage: image)
      var experimentalConfiguration = scene.scanConfiguration
      experimentalConfiguration.conditionalDualPass = AppleVisionConditionalDualPassOptions(
        mode: .enabled)
      let experimental = try AppleVisionScanner(configuration: experimentalConfiguration)
        .scan(cgImage: image)

      if baseline.fields != experimental.fields {
        failures.append("\(scene.identifier): fields changed")
      }
      let mismatches = GoldenFieldComparator.mismatches(
        expected: scene.expected,
        result: experimental.fields
      )
      failures.append(contentsOf: mismatches.map { "\(scene.identifier): \($0)" })
    }

    if !failures.isEmpty {
      Issue.record("Conditional stress regressions:\n\(failures.joined(separator: "\n"))")
    }
  }

  private func targetedSample(
    total: Double,
    targeted: Int,
    mismatches: Set<String>
  ) -> TargetedBenchmarkSample {
    TargetedBenchmarkSample(
      diagnostics: AppleVisionScanDiagnostics(
        stageTimings: [
          AppleVisionStageTiming(stage: .total, durationMilliseconds: total)
        ]
          + (targeted > 0
            ? [
              AppleVisionStageTiming(
                stage: .targetedReRecognition,
                durationMilliseconds: total / 2
              )
            ] : []),
        totalVisionRequestCount: 2 + targeted,
        rectangleRequestCount: 0,
        saliencyRequestCount: 0,
        textRecognitionRequestCount: 2 + targeted,
        primaryTextRecognitionRequestCount: 1 + targeted,
        secondaryTextRecognitionRequestCount: 1,
        targetedReRecognitionRequestCount: targeted,
        dualPassConfigured: true,
        dualPassExecuted: true,
        targetedReRecognitionConfigured: targeted > 0,
        targetedReRecognitionExecuted: targeted > 0,
        cardIsolationConfigured: false,
        cardIsolationAttempted: false,
        cardIsolationSucceeded: false,
        fullImageFallbackUsed: false
      ),
      mismatchedFields: mismatches,
      supportedFields: ["emailAddresses", "websites"],
      falseClearFields: [],
      reviewRecommended: false
    )
  }
#else
  @Test("Targeted re-recognition evidence requires Apple Vision")
  func targetedReRecognitionEvidenceUnavailable() {}
#endif
