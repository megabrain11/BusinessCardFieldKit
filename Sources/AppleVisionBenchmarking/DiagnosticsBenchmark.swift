import AppleVisionAdapter
import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(Vision)
  /// OCR pipeline configurations compared without changing the shipped default.
  public enum DiagnosticsBenchmarkConfiguration: String, Codable, CaseIterable, Sendable {
    case shippedDefault
    case conditionalDualPass
    case noDualPass
    case noTargetedReRecognition
    case singlePassWithoutTargetedReRecognition

    func apply(to configuration: inout AppleVisionScanConfiguration) {
      switch self {
      case .shippedDefault:
        break
      case .conditionalDualPass:
        configuration.conditionalDualPass = AppleVisionConditionalDualPassOptions(mode: .enabled)
      case .noDualPass:
        configuration.dualPassRecognition = false
      case .noTargetedReRecognition:
        configuration.performsTargetedReRecognition = false
      case .singlePassWithoutTargetedReRecognition:
        configuration.dualPassRecognition = false
        configuration.performsTargetedReRecognition = false
      }
    }
  }

  public struct BenchmarkDistribution: Codable, Equatable, Sendable {
    public var sampleCount: Int
    public var p50: Double
    public var p95: Double

    public init(values: [Double]) {
      let sorted = values.map { max($0, 0) }.sorted()
      sampleCount = sorted.count
      p50 = Self.percentile(0.50, sorted: sorted)
      p95 = Self.percentile(0.95, sorted: sorted)
    }

    private static func percentile(_ percentile: Double, sorted: [Double]) -> Double {
      guard !sorted.isEmpty else { return 0 }
      let rank = max(Int(ceil(percentile * Double(sorted.count))) - 1, 0)
      return sorted[min(rank, sorted.count - 1)]
    }
  }

  public struct BenchmarkStageSummary: Codable, Equatable, Sendable {
    public var stage: AppleVisionScanStage
    public var durationMilliseconds: BenchmarkDistribution
  }

  public struct BenchmarkRequestSummary: Codable, Equatable, Sendable {
    public var totalVision: BenchmarkDistribution
    public var textRecognition: BenchmarkDistribution
    public var secondaryTextRecognition: BenchmarkDistribution
    public var targetedReRecognition: BenchmarkDistribution
  }

  public struct BenchmarkTagSummary: Codable, Equatable, Sendable {
    public var tag: String
    public var sampleCount: Int
    public var fieldExactRate: Double
    public var totalDurationMilliseconds: BenchmarkDistribution
  }

  public struct BenchmarkDualPassDecisionSummary: Codable, Equatable, Sendable {
    public var reason: AppleVisionDualPassDecisionReason
    public var count: Int
  }

  public struct BenchmarkConfigurationReport: Codable, Equatable, Sendable {
    public var configuration: DiagnosticsBenchmarkConfiguration
    public var sampleCount: Int
    public var exactFieldCaseCount: Int
    public var mismatchedFieldCaseCount: Int
    public var fieldExactRate: Double
    public var reviewRecommendedRate: Double
    public var dualPassExecutionRate: Double
    public var dualPassSkipRate: Double
    public var dualPassSkipCount: Int
    public var dualPassDecisionSummaries: [BenchmarkDualPassDecisionSummary]
    public var targetedReRecognitionExecutionRate: Double
    public var cardIsolationSuccessRate: Double
    public var fullImageFallbackRate: Double
    public var totalDurationMilliseconds: BenchmarkDistribution
    public var stageDurations: [BenchmarkStageSummary]
    public var requests: BenchmarkRequestSummary
    public var tagSummaries: [BenchmarkTagSummary]
    public var omittedSmallTagGroupCount: Int
  }

  public struct ConditionalDualPassComparison: Codable, Equatable, Sendable {
    public var sampleCount: Int
    public var improvedExactCaseCount: Int
    public var regressedExactCaseCount: Int
    public var newReviewRecommendedCount: Int
    public var resolvedReviewRecommendedCount: Int
    public var totalP50DeltaMilliseconds: Double
    public var totalP95DeltaMilliseconds: Double
    public var secondaryRequestP50Delta: Double
    public var secondaryRequestP95Delta: Double
    public var secondaryRequestTotalDelta: Int
  }

  /// Aggregate-only report. It intentionally has no case identifier, OCR value,
  /// confidence, geometry, image, or path field.
  public struct DiagnosticsBenchmarkReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var reportSchemaVersion: Int
    public var corpusVersion: String
    public var layoutCount: Int
    public var caseCount: Int
    public var warmupRuns: Int
    public var measuredRuns: Int
    public var tagCoverage: [String: Int]
    public var configurations: [BenchmarkConfigurationReport]
    public var conditionalDualPassComparison: ConditionalDualPassComparison?
    public var evidenceLimitations: [String]

    public init(
      corpusVersion: String,
      layoutCount: Int,
      caseCount: Int,
      warmupRuns: Int,
      measuredRuns: Int,
      tagCoverage: [String: Int],
      configurations: [BenchmarkConfigurationReport],
      conditionalDualPassComparison: ConditionalDualPassComparison? = nil
    ) {
      reportSchemaVersion = Self.currentSchemaVersion
      self.corpusVersion = corpusVersion
      self.layoutCount = layoutCount
      self.caseCount = caseCount
      self.warmupRuns = warmupRuns
      self.measuredRuns = measuredRuns
      self.tagCoverage = tagCoverage
      self.configurations = configurations
      self.conditionalDualPassComparison = conditionalDualPassComparison
      evidenceLimitations = [
        "Synthetic Core Text scenes do not establish physical-device or real-photo performance.",
        "Stage spans can overlap; total duration is the only end-to-end latency measure.",
        "Provider timing varies with hardware, system load, and Vision runtime.",
      ]
    }
  }

  public struct DiagnosticsBenchmarkSample: Equatable, Sendable {
    public var diagnostics: AppleVisionScanDiagnostics
    public var mismatchedFieldCount: Int
    public var reviewRecommended: Bool
    public var tags: [String]

    public init(
      diagnostics: AppleVisionScanDiagnostics,
      mismatchedFieldCount: Int,
      reviewRecommended: Bool,
      tags: [String] = []
    ) {
      self.diagnostics = diagnostics
      self.mismatchedFieldCount = max(mismatchedFieldCount, 0)
      self.reviewRecommended = reviewRecommended
      self.tags = Array(Set(tags)).sorted()
    }
  }

  public enum DiagnosticsBenchmarkAggregator {
    public static func aggregate(
      configuration: DiagnosticsBenchmarkConfiguration,
      samples: [DiagnosticsBenchmarkSample]
    ) -> BenchmarkConfigurationReport {
      let count = samples.count
      let exactCount = samples.filter { $0.mismatchedFieldCount == 0 }.count
      let totalDurations = samples.map { sample in
        sample.diagnostics.stageTimings.first(where: { $0.stage == .total })?
          .durationMilliseconds ?? 0
      }
      let stageSummaries: [BenchmarkStageSummary] = AppleVisionScanStage.allCases.compactMap {
        stage -> BenchmarkStageSummary? in
        guard stage != .total else { return nil }
        let values = samples.compactMap { sample in
          sample.diagnostics.stageTimings.first(where: { $0.stage == stage })?
            .durationMilliseconds
        }
        guard !values.isEmpty else { return nil }
        return BenchmarkStageSummary(
          stage: stage,
          durationMilliseconds: BenchmarkDistribution(values: values)
        )
      }
      let tagGroups = Dictionary(
        grouping: samples.flatMap { sample in sample.tags.map { ($0, sample) } },
        by: { $0.0 }
      )
      let minimumAggregateGroupSize = 4
      let tagSummaries = tagGroups.compactMap { tag, taggedSamples -> BenchmarkTagSummary? in
        guard taggedSamples.count >= minimumAggregateGroupSize else { return nil }
        let values = taggedSamples.map(\.1)
        return BenchmarkTagSummary(
          tag: tag,
          sampleCount: values.count,
          fieldExactRate: rate(
            values.filter { $0.mismatchedFieldCount == 0 }.count, over: values.count),
          totalDurationMilliseconds: BenchmarkDistribution(
            values: values.map { totalDuration($0.diagnostics) }
          )
        )
      }.sorted { $0.tag < $1.tag }
      var decisionCounts: [AppleVisionDualPassDecisionReason: Int] = [:]
      for sample in samples {
        for item in sample.diagnostics.dualPassDecisionCounts {
          decisionCounts[item.reason, default: 0] += item.count
        }
      }
      let skipCount = samples.reduce(0) { $0 + $1.diagnostics.dualPassSkipCount }

      return BenchmarkConfigurationReport(
        configuration: configuration,
        sampleCount: count,
        exactFieldCaseCount: exactCount,
        mismatchedFieldCaseCount: count - exactCount,
        fieldExactRate: rate(exactCount, over: count),
        reviewRecommendedRate: rate(
          samples.filter(\.reviewRecommended).count, over: count),
        dualPassExecutionRate: rate(
          samples.filter { $0.diagnostics.dualPassExecuted }.count, over: count),
        dualPassSkipRate: rate(
          samples.filter { $0.diagnostics.dualPassSkipCount > 0 }.count, over: count),
        dualPassSkipCount: skipCount,
        dualPassDecisionSummaries: AppleVisionDualPassDecisionReason.allCases.compactMap {
          reason in
          decisionCounts[reason].map {
            BenchmarkDualPassDecisionSummary(reason: reason, count: $0)
          }
        },
        targetedReRecognitionExecutionRate: rate(
          samples.filter { $0.diagnostics.targetedReRecognitionExecuted }.count,
          over: count
        ),
        cardIsolationSuccessRate: rate(
          samples.filter { $0.diagnostics.cardIsolationSucceeded }.count, over: count),
        fullImageFallbackRate: rate(
          samples.filter { $0.diagnostics.fullImageFallbackUsed }.count, over: count),
        totalDurationMilliseconds: BenchmarkDistribution(values: totalDurations),
        stageDurations: stageSummaries,
        requests: BenchmarkRequestSummary(
          totalVision: BenchmarkDistribution(
            values: samples.map { Double($0.diagnostics.totalVisionRequestCount) }),
          textRecognition: BenchmarkDistribution(
            values: samples.map { Double($0.diagnostics.textRecognitionRequestCount) }),
          secondaryTextRecognition: BenchmarkDistribution(
            values: samples.map { Double($0.diagnostics.secondaryTextRecognitionRequestCount) }),
          targetedReRecognition: BenchmarkDistribution(
            values: samples.map { Double($0.diagnostics.targetedReRecognitionRequestCount) })
        ),
        tagSummaries: tagSummaries,
        omittedSmallTagGroupCount: tagGroups.values.filter {
          $0.count < minimumAggregateGroupSize
        }.count
      )
    }

    private static func totalDuration(_ diagnostics: AppleVisionScanDiagnostics) -> Double {
      diagnostics.stageTimings.first(where: { $0.stage == .total })?
        .durationMilliseconds ?? 0
    }

    private static func rate(_ numerator: Int, over denominator: Int) -> Double {
      guard denominator > 0 else { return 0 }
      return Double(numerator) / Double(denominator)
    }

    public static func conditionalComparison(
      baseline: [DiagnosticsBenchmarkSample],
      experiment: [DiagnosticsBenchmarkSample]
    ) -> ConditionalDualPassComparison? {
      guard baseline.count == experiment.count, !baseline.isEmpty else { return nil }
      let pairs = Array(zip(baseline, experiment))
      let baselineReport = aggregate(configuration: .shippedDefault, samples: baseline)
      let experimentReport = aggregate(configuration: .conditionalDualPass, samples: experiment)
      return ConditionalDualPassComparison(
        sampleCount: pairs.count,
        improvedExactCaseCount: pairs.filter {
          $0.0.mismatchedFieldCount > 0 && $0.1.mismatchedFieldCount == 0
        }.count,
        regressedExactCaseCount: pairs.filter {
          $0.0.mismatchedFieldCount == 0 && $0.1.mismatchedFieldCount > 0
        }.count,
        newReviewRecommendedCount: pairs.filter {
          !$0.0.reviewRecommended && $0.1.reviewRecommended
        }.count,
        resolvedReviewRecommendedCount: pairs.filter {
          $0.0.reviewRecommended && !$0.1.reviewRecommended
        }.count,
        totalP50DeltaMilliseconds: experimentReport.totalDurationMilliseconds.p50
          - baselineReport.totalDurationMilliseconds.p50,
        totalP95DeltaMilliseconds: experimentReport.totalDurationMilliseconds.p95
          - baselineReport.totalDurationMilliseconds.p95,
        secondaryRequestP50Delta: experimentReport.requests.secondaryTextRecognition.p50
          - baselineReport.requests.secondaryTextRecognition.p50,
        secondaryRequestP95Delta: experimentReport.requests.secondaryTextRecognition.p95
          - baselineReport.requests.secondaryTextRecognition.p95,
        secondaryRequestTotalDelta: experiment.reduce(0) {
          $0 + $1.diagnostics.secondaryTextRecognitionRequestCount
        }
          - baseline.reduce(0) {
            $0 + $1.diagnostics.secondaryTextRecognitionRequestCount
          }
      )
    }
  }

  public enum DiagnosticsBenchmarkError: Error, Equatable {
    case diagnosticsMissing
    case emptyCorpus
    case invalidRunCount
  }

  public struct DiagnosticsBenchmarkRunner: Sendable {
    public var warmupRuns: Int
    public var measuredRuns: Int

    public init(warmupRuns: Int = 1, measuredRuns: Int = 3) {
      self.warmupRuns = warmupRuns
      self.measuredRuns = measuredRuns
    }

    public func run(manifest: GoldenCorpusManifest) throws -> DiagnosticsBenchmarkReport {
      let cases = try manifest.expandedCases()
      guard !cases.isEmpty else { throw DiagnosticsBenchmarkError.emptyCorpus }
      guard warmupRuns >= 0, measuredRuns > 0 else {
        throw DiagnosticsBenchmarkError.invalidRunCount
      }

      var samplesByConfiguration:
        [DiagnosticsBenchmarkConfiguration: [DiagnosticsBenchmarkSample]] =
          [:]
      let pairedConfigurations: [DiagnosticsBenchmarkConfiguration] = [
        .shippedDefault, .conditionalDualPass,
      ]
      for run in 0..<(warmupRuns + measuredRuns) {
        for (index, scene) in cases.enumerated() {
          let order =
            (run + index).isMultiple(of: 2)
            ? pairedConfigurations : Array(pairedConfigurations.reversed())
          for benchmarkConfiguration in order {
            let result = try scan(scene, benchmarkConfiguration: benchmarkConfiguration)
            guard run >= warmupRuns else { continue }
            guard let diagnostics = result.diagnostics else {
              throw DiagnosticsBenchmarkError.diagnosticsMissing
            }
            samplesByConfiguration[benchmarkConfiguration, default: []].append(
              sample(scene: scene, result: result, diagnostics: diagnostics)
            )
          }
        }
      }

      for benchmarkConfiguration in DiagnosticsBenchmarkConfiguration.allCases
      where !pairedConfigurations.contains(benchmarkConfiguration) {
        for _ in 0..<warmupRuns {
          for scene in cases {
            _ = try scan(scene, benchmarkConfiguration: benchmarkConfiguration)
          }
        }

        var samples: [DiagnosticsBenchmarkSample] = []
        for _ in 0..<measuredRuns {
          for scene in cases {
            let result = try scan(scene, benchmarkConfiguration: benchmarkConfiguration)
            guard let diagnostics = result.diagnostics else {
              throw DiagnosticsBenchmarkError.diagnosticsMissing
            }
            samples.append(sample(scene: scene, result: result, diagnostics: diagnostics))
          }
        }
        samplesByConfiguration[benchmarkConfiguration] = samples
      }
      let reports = DiagnosticsBenchmarkConfiguration.allCases.map { configuration in
        DiagnosticsBenchmarkAggregator.aggregate(
          configuration: configuration,
          samples: samplesByConfiguration[configuration] ?? []
        )
      }

      let conditionalComparison = DiagnosticsBenchmarkAggregator.conditionalComparison(
        baseline: samplesByConfiguration[.shippedDefault] ?? [],
        experiment: samplesByConfiguration[.conditionalDualPass] ?? []
      )

      return DiagnosticsBenchmarkReport(
        corpusVersion: manifest.corpusVersion,
        layoutCount: manifest.layouts.count,
        caseCount: cases.count,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        tagCoverage: tagCoverage(cases),
        configurations: reports,
        conditionalDualPassComparison: conditionalComparison
      )
    }

    private func scan(
      _ scene: GoldenSceneCase,
      benchmarkConfiguration: DiagnosticsBenchmarkConfiguration
    ) throws -> AppleVisionScanResult {
      var configuration = scene.scanConfiguration
      benchmarkConfiguration.apply(to: &configuration)
      configuration.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
      return try AppleVisionScanner(configuration: configuration).scan(
        cgImage: GoldenSceneRenderer.render(scene)
      )
    }

    private func sample(
      scene: GoldenSceneCase,
      result: AppleVisionScanResult,
      diagnostics: AppleVisionScanDiagnostics
    ) -> DiagnosticsBenchmarkSample {
      DiagnosticsBenchmarkSample(
        diagnostics: diagnostics,
        mismatchedFieldCount: GoldenFieldComparison.mismatchedFields(
          expected: scene.expected,
          result: result.fields
        ).count,
        reviewRecommended: result.fields.warnings.contains(.reviewRecommended),
        tags: scene.tags
      )
    }

    private func tagCoverage(_ cases: [GoldenSceneCase]) -> [String: Int] {
      var result: [String: Int] = [:]
      for scene in cases {
        for tag in scene.tags { result[tag, default: 0] += 1 }
      }
      return result
    }
  }
#endif
