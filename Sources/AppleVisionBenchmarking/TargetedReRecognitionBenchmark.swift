import AppleVisionAdapter
import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(Vision)
  public enum TargetedBenchmarkConfiguration: String, Codable, CaseIterable, Sendable {
    case enabled
    case disabled
  }

  public struct TargetedFieldSummary: Codable, Equatable, Sendable {
    public var field: String
    public var sampleCount: Int
    public var supportedSampleCount: Int
    public var exactRate: Double
    public var falseClearCount: Int
  }

  public struct TargetedConfigurationReport: Codable, Equatable, Sendable {
    public var configuration: TargetedBenchmarkConfiguration
    public var sampleCount: Int
    public var exactCaseCount: Int
    public var mismatchedCaseCount: Int
    public var exactCaseRate: Double
    public var reviewRecommendedRate: Double
    public var targetedExecutionRate: Double
    public var falseClearCount: Int
    public var totalDurationMilliseconds: BenchmarkDistribution
    public var targetedDurationMilliseconds: BenchmarkDistribution?
    public var targetedRequestCount: BenchmarkDistribution
    public var fieldSummaries: [TargetedFieldSummary]
  }

  public struct TargetedPairSummary: Codable, Equatable, Sendable {
    public var recoveredFieldCount: Int
    public var regressedFieldCount: Int
    public var newReviewRecommendedCount: Int
    public var resolvedReviewRecommendedCount: Int
  }

  /// Aggregate-only targeted re-recognition evidence. The payload has no OCR,
  /// image, path, confidence, geometry, or case-identity field.
  public struct TargetedReRecognitionBenchmarkReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var reportSchemaVersion: Int
    public var corpusVersion: String
    public var layoutCount: Int
    public var caseCount: Int
    public var warmupRuns: Int
    public var measuredRuns: Int
    public var defaultThresholdCaseCount: Int
    public var calibratedThresholdCaseCount: Int
    public var nonExecutionControlCaseCount: Int
    public var configurations: [TargetedConfigurationReport]
    public var pairedComparison: TargetedPairSummary
    public var evidenceLimitations: [String]

    public init(
      corpusVersion: String,
      layoutCount: Int,
      caseCount: Int,
      warmupRuns: Int,
      measuredRuns: Int,
      defaultThresholdCaseCount: Int,
      calibratedThresholdCaseCount: Int,
      nonExecutionControlCaseCount: Int,
      configurations: [TargetedConfigurationReport],
      pairedComparison: TargetedPairSummary
    ) {
      reportSchemaVersion = Self.currentSchemaVersion
      self.corpusVersion = corpusVersion
      self.layoutCount = layoutCount
      self.caseCount = caseCount
      self.warmupRuns = warmupRuns
      self.measuredRuns = measuredRuns
      self.defaultThresholdCaseCount = defaultThresholdCaseCount
      self.calibratedThresholdCaseCount = calibratedThresholdCaseCount
      self.nonExecutionControlCaseCount = nonExecutionControlCaseCount
      self.configurations = configurations
      self.pairedComparison = pairedComparison
      evidenceLimitations = [
        "Synthetic scenes do not establish physical-device or real-photo performance.",
        "Calibrated-threshold cases measure stage behavior, not the shipped threshold policy.",
        "Only total duration is end-to-end; targeted spans can contain recognition requests.",
      ]
    }
  }

  public struct TargetedBenchmarkSample: Equatable, Sendable {
    public var diagnostics: AppleVisionScanDiagnostics
    public var mismatchedFields: Set<String>
    public var supportedFields: Set<String>
    public var falseClearFields: Set<String>
    public var reviewRecommended: Bool

    public init(
      diagnostics: AppleVisionScanDiagnostics,
      mismatchedFields: Set<String>,
      supportedFields: Set<String>,
      falseClearFields: Set<String>,
      reviewRecommended: Bool
    ) {
      self.diagnostics = diagnostics
      self.mismatchedFields = mismatchedFields
      self.supportedFields = supportedFields
      self.falseClearFields = falseClearFields
      self.reviewRecommended = reviewRecommended
    }
  }

  public struct TargetedPairedSample: Equatable, Sendable {
    public var enabled: TargetedBenchmarkSample
    public var disabled: TargetedBenchmarkSample

    public init(enabled: TargetedBenchmarkSample, disabled: TargetedBenchmarkSample) {
      self.enabled = enabled
      self.disabled = disabled
    }
  }

  public enum TargetedBenchmarkAggregator {
    public static func configurationReport(
      configuration: TargetedBenchmarkConfiguration,
      samples: [TargetedBenchmarkSample]
    ) -> TargetedConfigurationReport {
      let exactCases = samples.filter { $0.mismatchedFields.isEmpty }.count
      let targetedDurations = samples.compactMap { sample in
        sample.diagnostics.stageTimings.first(where: {
          $0.stage == .targetedReRecognition
        })?.durationMilliseconds
      }
      let fieldSummaries = CardField.allCases.map { field in
        let key = field.rawValue
        return TargetedFieldSummary(
          field: key,
          sampleCount: samples.count,
          supportedSampleCount: samples.filter { $0.supportedFields.contains(key) }.count,
          exactRate: rate(
            samples.filter { !$0.mismatchedFields.contains(key) }.count,
            over: samples.count
          ),
          falseClearCount: samples.filter { $0.falseClearFields.contains(key) }.count
        )
      }
      return TargetedConfigurationReport(
        configuration: configuration,
        sampleCount: samples.count,
        exactCaseCount: exactCases,
        mismatchedCaseCount: samples.count - exactCases,
        exactCaseRate: rate(exactCases, over: samples.count),
        reviewRecommendedRate: rate(
          samples.filter(\.reviewRecommended).count, over: samples.count),
        targetedExecutionRate: rate(
          samples.filter { $0.diagnostics.targetedReRecognitionExecuted }.count,
          over: samples.count
        ),
        falseClearCount: samples.reduce(0) { $0 + $1.falseClearFields.count },
        totalDurationMilliseconds: BenchmarkDistribution(
          values: samples.map { totalDuration($0.diagnostics) }
        ),
        targetedDurationMilliseconds: targetedDurations.isEmpty
          ? nil : BenchmarkDistribution(values: targetedDurations),
        targetedRequestCount: BenchmarkDistribution(
          values: samples.map {
            Double($0.diagnostics.targetedReRecognitionRequestCount)
          }
        ),
        fieldSummaries: fieldSummaries
      )
    }

    public static func pairedSummary(_ samples: [TargetedPairedSample]) -> TargetedPairSummary {
      TargetedPairSummary(
        recoveredFieldCount: samples.reduce(0) {
          $0 + $1.disabled.mismatchedFields.subtracting($1.enabled.mismatchedFields).count
        },
        regressedFieldCount: samples.reduce(0) {
          $0 + $1.enabled.mismatchedFields.subtracting($1.disabled.mismatchedFields).count
        },
        newReviewRecommendedCount: samples.filter {
          $0.enabled.reviewRecommended && !$0.disabled.reviewRecommended
        }.count,
        resolvedReviewRecommendedCount: samples.filter {
          !$0.enabled.reviewRecommended && $0.disabled.reviewRecommended
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
  }

  public struct TargetedReRecognitionBenchmarkRunner: Sendable {
    public var warmupRuns: Int
    public var measuredRuns: Int

    public init(warmupRuns: Int = 1, measuredRuns: Int = 3) {
      self.warmupRuns = warmupRuns
      self.measuredRuns = measuredRuns
    }

    public func run(manifest: GoldenCorpusManifest) throws
      -> TargetedReRecognitionBenchmarkReport
    {
      let cases = try manifest.expandedCases()
      guard !cases.isEmpty else { throw DiagnosticsBenchmarkError.emptyCorpus }
      guard warmupRuns >= 0, measuredRuns > 0 else {
        throw DiagnosticsBenchmarkError.invalidRunCount
      }

      for _ in 0..<warmupRuns {
        for (index, scene) in cases.enumerated() {
          _ = try scanPair(scene, enabledFirst: index.isMultiple(of: 2))
        }
      }

      var pairs: [TargetedPairedSample] = []
      for run in 0..<measuredRuns {
        for (index, scene) in cases.enumerated() {
          pairs.append(
            try scanPair(scene, enabledFirst: (run + index).isMultiple(of: 2))
          )
        }
      }

      return TargetedReRecognitionBenchmarkReport(
        corpusVersion: manifest.corpusVersion,
        layoutCount: manifest.layouts.count,
        caseCount: cases.count,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        defaultThresholdCaseCount: cases.filter { $0.tags.contains("default-threshold") }.count,
        calibratedThresholdCaseCount: cases.filter {
          $0.tags.contains("calibrated-threshold")
        }.count,
        nonExecutionControlCaseCount: cases.filter {
          $0.tags.contains("nonexecution-control")
        }.count,
        configurations: [
          TargetedBenchmarkAggregator.configurationReport(
            configuration: .enabled,
            samples: pairs.map(\.enabled)
          ),
          TargetedBenchmarkAggregator.configurationReport(
            configuration: .disabled,
            samples: pairs.map(\.disabled)
          ),
        ],
        pairedComparison: TargetedBenchmarkAggregator.pairedSummary(pairs)
      )
    }

    private func scanPair(_ scene: GoldenSceneCase, enabledFirst: Bool) throws
      -> TargetedPairedSample
    {
      let enabled: TargetedBenchmarkSample
      let disabled: TargetedBenchmarkSample
      if enabledFirst {
        enabled = try scan(scene, targetedEnabled: true)
        disabled = try scan(scene, targetedEnabled: false)
      } else {
        disabled = try scan(scene, targetedEnabled: false)
        enabled = try scan(scene, targetedEnabled: true)
      }
      return TargetedPairedSample(enabled: enabled, disabled: disabled)
    }

    private func scan(_ scene: GoldenSceneCase, targetedEnabled: Bool) throws
      -> TargetedBenchmarkSample
    {
      var configuration = scene.scanConfiguration
      configuration.performsTargetedReRecognition = targetedEnabled
      configuration.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
      let result = try AppleVisionScanner(configuration: configuration).scan(
        cgImage: GoldenSceneRenderer.render(scene)
      )
      guard let diagnostics = result.diagnostics else {
        throw DiagnosticsBenchmarkError.diagnosticsMissing
      }
      let supported = Set(
        scene.expected.compactMap { key, values in
          values.isEmpty ? nil : key
        })
      let falseClears = Set(
        CardField.allCases.compactMap { field -> String? in
          guard supported.contains(field.rawValue), result.fields.values(for: field).isEmpty else {
            return nil
          }
          return field.rawValue
        })
      return TargetedBenchmarkSample(
        diagnostics: diagnostics,
        mismatchedFields: Set(
          GoldenFieldComparison.mismatchedFields(
            expected: scene.expected,
            result: result.fields
          )
        ),
        supportedFields: supported,
        falseClearFields: falseClears,
        reviewRecommended: result.fields.warnings.contains(.reviewRecommended)
      )
    }
  }
#endif
