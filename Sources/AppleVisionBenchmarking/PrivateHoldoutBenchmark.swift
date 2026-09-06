import AppleVisionAdapter
import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  /// External-only manifest for transient private image evaluation.
  public struct PrivateHoldoutManifest: Decodable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var cases: [PrivateHoldoutCase]

    public init(data: Data) throws {
      self = try JSONDecoder().decode(Self.self, from: data)
      guard schemaVersion == Self.currentSchemaVersion else {
        throw PrivateHoldoutError.unsupportedSchemaVersion
      }
      guard !cases.isEmpty else { throw PrivateHoldoutError.emptyCorpus }
    }

    func validatedCases(root: URL) throws -> [ValidatedPrivateHoldoutCase] {
      let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
      var references = Set<String>()
      return try cases.map { record in
        guard !record.image.isEmpty, !record.image.hasPrefix("/") else {
          throw PrivateHoldoutError.invalidImageReference
        }
        let components = record.image.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("."), !components.contains("")
        else { throw PrivateHoldoutError.invalidImageReference }
        guard references.insert(record.image).inserted else {
          throw PrivateHoldoutError.duplicateImageReference
        }
        let imageURL = resolvedRoot.appendingPathComponent(record.image)
          .standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix =
          resolvedRoot.path.hasSuffix("/")
          ? resolvedRoot.path : resolvedRoot.path + "/"
        guard imageURL.path.hasPrefix(rootPrefix) else {
          throw PrivateHoldoutError.imageOutsideCorpusRoot
        }
        guard imageURL.isFileURL,
          (try? imageURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else { throw PrivateHoldoutError.imageUnavailable }
        let knownFields = Set(CardField.allCases.map(\.rawValue))
        guard Set(record.expected.keys).isSubset(of: knownFields) else {
          throw PrivateHoldoutError.unknownExpectedField
        }
        return ValidatedPrivateHoldoutCase(record: record, imageURL: imageURL)
      }.sorted { $0.record.image < $1.record.image }
    }
  }

  /// One private image reference and its transient expected fields.
  public struct PrivateHoldoutCase: Decodable, Sendable {
    public var image: String
    public var expected: [String: [String]]
    public var recognitionLanguages: [String]?
    public var automaticallyDetectsLanguage: Bool?
    public var attemptsCardIsolation: Bool?
  }

  public enum PrivateHoldoutError: Error, Equatable {
    case unsupportedSchemaVersion
    case emptyCorpus
    case invalidImageReference
    case duplicateImageReference
    case imageOutsideCorpusRoot
    case imageUnavailable
    case unknownExpectedField
    case invalidRunCount
    case diagnosticsMissing
  }

  public enum PrivateHoldoutStatus: String, Codable, Sendable {
    case completed
    case skipped
  }

  public enum PrivateHoldoutSkipReason: String, Codable, Sendable {
    case privateCorpusUnavailable
  }

  /// Redacted command envelope used for both completed and safely skipped runs.
  public struct PrivateHoldoutCommandReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var reportSchemaVersion: Int
    public var status: PrivateHoldoutStatus
    public var skipReason: PrivateHoldoutSkipReason?
    public var report: PrivateHoldoutBenchmarkReport?

    public static var skipped: Self {
      Self(
        reportSchemaVersion: currentSchemaVersion,
        status: .skipped,
        skipReason: .privateCorpusUnavailable,
        report: nil
      )
    }

    public static func completed(_ report: PrivateHoldoutBenchmarkReport) -> Self {
      Self(
        reportSchemaVersion: currentSchemaVersion,
        status: .completed,
        skipReason: nil,
        report: report
      )
    }
  }

  public enum PrivateEvidenceAssessment: String, Codable, Sendable {
    case insufficientNaturalExecutions
    case rejectPolicyChange
    case eligibleForHumanReview
  }

  public struct PrivateConfidenceInterval: Codable, Equatable, Sendable {
    public var estimate: Double
    public var lowerBound: Double
    public var upperBound: Double
  }

  public struct PrivateBootstrapReport: Codable, Equatable, Sendable {
    public var iterations: Int
    public var confidenceLevel: Double
    public var exactCaseRateDelta: PrivateConfidenceInterval
    public var netRecoveredFieldsPerCase: PrivateConfidenceInterval
    public var totalLatencyP95DeltaMilliseconds: PrivateConfidenceInterval
  }

  public struct PrivateConfigurationReport: Codable, Equatable, Sendable {
    public var configuration: TargetedBenchmarkConfiguration
    public var sampleCount: Int
    public var exactCaseRate: Double
    public var reviewRecommendedRate: Double
    public var targetedExecutionRate: Double
    public var falseClearCount: Int
    public var cardIsolationSuccessCount: Int
    public var fullImageFallbackCount: Int
    public var totalDurationMilliseconds: BenchmarkDistribution
    public var targetedDurationMilliseconds: BenchmarkDistribution?
    public var totalVisionRequestCount: BenchmarkDistribution
    public var targetedRequestCount: BenchmarkDistribution
    public var fieldSummaries: [TargetedFieldSummary]
  }

  /// Aggregate-only real-photo holdout report with no source identity or OCR content.
  public struct PrivateHoldoutBenchmarkReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var reportSchemaVersion: Int
    public var corpusSchemaVersion: Int
    public var caseCount: Int
    public var warmupRuns: Int
    public var measuredRuns: Int
    public var naturalExecutionCaseCount: Int
    public var configurations: [PrivateConfigurationReport]
    public var pairedComparison: TargetedPairSummary
    public var bootstrap: PrivateBootstrapReport
    public var assessment: PrivateEvidenceAssessment
    public var evidenceLimitations: [String]
  }

  struct ValidatedPrivateHoldoutCase: Sendable {
    var record: PrivateHoldoutCase
    var imageURL: URL
  }

  struct PrivatePairedObservation: Equatable, Sendable {
    var caseIndex: Int
    var enabled: TargetedBenchmarkSample
    var disabled: TargetedBenchmarkSample

    var pair: TargetedPairedSample {
      TargetedPairedSample(enabled: enabled, disabled: disabled)
    }
  }

  enum PrivateHoldoutAggregator {
    static let minimumNaturalExecutionCases = 4

    static func makeReport(
      corpusSchemaVersion: Int,
      caseCount: Int,
      warmupRuns: Int,
      measuredRuns: Int,
      bootstrapIterations: Int,
      observations: [PrivatePairedObservation]
    ) -> PrivateHoldoutBenchmarkReport {
      let sorted = observations.sorted {
        (
          $0.caseIndex, totalDuration($0.enabled.diagnostics),
          totalDuration($0.disabled.diagnostics)
        )
          < (
            $1.caseIndex, totalDuration($1.enabled.diagnostics),
            totalDuration($1.disabled.diagnostics)
          )
      }
      let naturalExecutions = Set(
        sorted.compactMap { observation in
          observation.enabled.diagnostics.targetedReRecognitionExecuted
            ? observation.caseIndex : nil
        })
      let enabled = configurationReport(
        configuration: .enabled, samples: sorted.map(\.enabled))
      let disabled = configurationReport(
        configuration: .disabled, samples: sorted.map(\.disabled))
      let paired = TargetedBenchmarkAggregator.pairedSummary(sorted.map(\.pair))
      let excessiveLatency =
        enabled.totalDurationMilliseconds.p95
        - disabled.totalDurationMilliseconds.p95
        > max(disabled.totalDurationMilliseconds.p95 * 0.5, 100)
      let assessment: PrivateEvidenceAssessment
      if naturalExecutions.count < minimumNaturalExecutionCases {
        assessment = .insufficientNaturalExecutions
      } else if paired.regressedFieldCount > 0 || excessiveLatency {
        assessment = .rejectPolicyChange
      } else {
        assessment = .eligibleForHumanReview
      }
      return PrivateHoldoutBenchmarkReport(
        reportSchemaVersion: PrivateHoldoutBenchmarkReport.currentSchemaVersion,
        corpusSchemaVersion: corpusSchemaVersion,
        caseCount: caseCount,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        naturalExecutionCaseCount: naturalExecutions.count,
        configurations: [enabled, disabled],
        pairedComparison: paired,
        bootstrap: bootstrap(
          observations: sorted,
          iterations: bootstrapIterations
        ),
        assessment: assessment,
        evidenceLimitations: [
          "Private aggregate results cannot identify which source triggered a stage.",
          "Timing varies with hardware, system load, and Vision runtime.",
          "Eligibility means human review is permitted, not that production policy is approved.",
        ]
      )
    }

    static func configurationReport(
      configuration: TargetedBenchmarkConfiguration,
      samples: [TargetedBenchmarkSample]
    ) -> PrivateConfigurationReport {
      let base = TargetedBenchmarkAggregator.configurationReport(
        configuration: configuration,
        samples: samples
      )
      return PrivateConfigurationReport(
        configuration: configuration,
        sampleCount: samples.count,
        exactCaseRate: base.exactCaseRate,
        reviewRecommendedRate: base.reviewRecommendedRate,
        targetedExecutionRate: base.targetedExecutionRate,
        falseClearCount: base.falseClearCount,
        cardIsolationSuccessCount: samples.filter {
          $0.diagnostics.cardIsolationSucceeded
        }.count,
        fullImageFallbackCount: samples.filter {
          $0.diagnostics.fullImageFallbackUsed
        }.count,
        totalDurationMilliseconds: base.totalDurationMilliseconds,
        targetedDurationMilliseconds: base.targetedDurationMilliseconds,
        totalVisionRequestCount: BenchmarkDistribution(
          values: samples.map { Double($0.diagnostics.totalVisionRequestCount) }
        ),
        targetedRequestCount: base.targetedRequestCount,
        fieldSummaries: base.fieldSummaries
      )
    }

    static func bootstrap(
      observations: [PrivatePairedObservation],
      iterations: Int
    ) -> PrivateBootstrapReport {
      let grouped = Dictionary(grouping: observations, by: \.caseIndex)
      let clusters = grouped.keys.sorted().compactMap { grouped[$0] }
      let point = statistics(observations)
      guard !clusters.isEmpty, iterations > 0 else {
        let zero = PrivateConfidenceInterval(
          estimate: point.exactDelta, lowerBound: point.exactDelta,
          upperBound: point.exactDelta)
        return PrivateBootstrapReport(
          iterations: max(iterations, 0),
          confidenceLevel: 0.95,
          exactCaseRateDelta: zero,
          netRecoveredFieldsPerCase: PrivateConfidenceInterval(
            estimate: point.netRecovered, lowerBound: point.netRecovered,
            upperBound: point.netRecovered),
          totalLatencyP95DeltaMilliseconds: PrivateConfidenceInterval(
            estimate: point.latencyP95Delta, lowerBound: point.latencyP95Delta,
            upperBound: point.latencyP95Delta)
        )
      }

      var generator = PrivateSplitMix64(seed: 0x4255_5349_4E45_5353)
      var exactDeltas: [Double] = []
      var netRecoveries: [Double] = []
      var latencyDeltas: [Double] = []
      exactDeltas.reserveCapacity(iterations)
      netRecoveries.reserveCapacity(iterations)
      latencyDeltas.reserveCapacity(iterations)
      for _ in 0..<iterations {
        var sampled: [PrivatePairedObservation] = []
        for _ in clusters.indices {
          sampled.append(contentsOf: clusters[generator.nextIndex(upperBound: clusters.count)])
        }
        let value = statistics(sampled)
        exactDeltas.append(value.exactDelta)
        netRecoveries.append(value.netRecovered)
        latencyDeltas.append(value.latencyP95Delta)
      }
      return PrivateBootstrapReport(
        iterations: iterations,
        confidenceLevel: 0.95,
        exactCaseRateDelta: interval(estimate: point.exactDelta, values: exactDeltas),
        netRecoveredFieldsPerCase: interval(
          estimate: point.netRecovered, values: netRecoveries),
        totalLatencyP95DeltaMilliseconds: interval(
          estimate: point.latencyP95Delta, values: latencyDeltas)
      )
    }

    private static func statistics(_ observations: [PrivatePairedObservation]) -> (
      exactDelta: Double, netRecovered: Double, latencyP95Delta: Double
    ) {
      guard !observations.isEmpty else { return (0, 0, 0) }
      let enabledExact = observations.filter { $0.enabled.mismatchedFields.isEmpty }.count
      let disabledExact = observations.filter { $0.disabled.mismatchedFields.isEmpty }.count
      let pairSummary = TargetedBenchmarkAggregator.pairedSummary(observations.map(\.pair))
      let count = Double(observations.count)
      let enabledP95 = BenchmarkDistribution(
        values: observations.map { totalDuration($0.enabled.diagnostics) }
      ).p95
      let disabledP95 = BenchmarkDistribution(
        values: observations.map { totalDuration($0.disabled.diagnostics) }
      ).p95
      return (
        Double(enabledExact - disabledExact) / count,
        Double(pairSummary.recoveredFieldCount - pairSummary.regressedFieldCount) / count,
        enabledP95 - disabledP95
      )
    }

    private static func interval(
      estimate: Double, values: [Double]
    ) -> PrivateConfidenceInterval {
      let sorted = values.sorted()
      guard !sorted.isEmpty else {
        return PrivateConfidenceInterval(
          estimate: estimate, lowerBound: estimate, upperBound: estimate)
      }
      let lowerIndex = min(Int(floor(Double(sorted.count - 1) * 0.025)), sorted.count - 1)
      let upperIndex = min(Int(ceil(Double(sorted.count - 1) * 0.975)), sorted.count - 1)
      return PrivateConfidenceInterval(
        estimate: estimate,
        lowerBound: sorted[lowerIndex],
        upperBound: sorted[upperIndex]
      )
    }

    private static func totalDuration(_ diagnostics: AppleVisionScanDiagnostics) -> Double {
      diagnostics.stageTimings.first(where: { $0.stage == .total })?
        .durationMilliseconds ?? 0
    }
  }

  /// Reads transient images from one external root and emits aggregate paired evidence only.
  public struct PrivateHoldoutBenchmarkRunner: Sendable {
    public var warmupRuns: Int
    public var measuredRuns: Int
    public var bootstrapIterations: Int

    public init(warmupRuns: Int = 1, measuredRuns: Int = 3, bootstrapIterations: Int = 2_000) {
      self.warmupRuns = warmupRuns
      self.measuredRuns = measuredRuns
      self.bootstrapIterations = bootstrapIterations
    }

    public func run(manifest: PrivateHoldoutManifest, root: URL) throws
      -> PrivateHoldoutBenchmarkReport
    {
      guard warmupRuns >= 0, measuredRuns >= 3, bootstrapIterations > 0 else {
        throw PrivateHoldoutError.invalidRunCount
      }
      let cases = try manifest.validatedCases(root: root)
      for run in 0..<warmupRuns {
        for (index, record) in cases.enumerated() {
          _ = try scanPair(
            record,
            enabledFirst: (run + index).isMultiple(of: 2)
          )
        }
      }

      var observations: [PrivatePairedObservation] = []
      for run in 0..<measuredRuns {
        for (index, record) in cases.enumerated() {
          let pair = try scanPair(
            record,
            enabledFirst: (run + index).isMultiple(of: 2)
          )
          observations.append(
            PrivatePairedObservation(
              caseIndex: index,
              enabled: pair.enabled,
              disabled: pair.disabled
            )
          )
        }
      }

      return PrivateHoldoutAggregator.makeReport(
        corpusSchemaVersion: manifest.schemaVersion,
        caseCount: cases.count,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        bootstrapIterations: bootstrapIterations,
        observations: observations
      )
    }

    private func scanPair(
      _ record: ValidatedPrivateHoldoutCase,
      enabledFirst: Bool
    ) throws -> TargetedPairedSample {
      let imageData = try Data(contentsOf: record.imageURL)
      let enabled: TargetedBenchmarkSample
      let disabled: TargetedBenchmarkSample
      if enabledFirst {
        enabled = try scan(record.record, imageData: imageData, targetedEnabled: true)
        disabled = try scan(record.record, imageData: imageData, targetedEnabled: false)
      } else {
        disabled = try scan(record.record, imageData: imageData, targetedEnabled: false)
        enabled = try scan(record.record, imageData: imageData, targetedEnabled: true)
      }
      return TargetedPairedSample(enabled: enabled, disabled: disabled)
    }

    private func scan(
      _ record: PrivateHoldoutCase,
      imageData: Data,
      targetedEnabled: Bool
    ) throws -> TargetedBenchmarkSample {
      let configuration = AppleVisionScanConfiguration(
        recognitionLanguages: record.recognitionLanguages ?? [],
        automaticallyDetectsLanguage: record.automaticallyDetectsLanguage ?? true,
        cardRegion: AppleVisionCardRegionConfiguration(
          mode: (record.attemptsCardIsolation ?? true) ? .automatic : .disabled
        ),
        performsTargetedReRecognition: targetedEnabled,
        diagnostics: AppleVisionDiagnosticsOptions(isEnabled: true)
      )
      let result = try AppleVisionScanner(configuration: configuration).scan(imageData: imageData)
      guard let diagnostics = result.diagnostics else {
        throw PrivateHoldoutError.diagnosticsMissing
      }
      let supported = Set(
        record.expected.compactMap { key, values in values.isEmpty ? nil : key })
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
            expected: record.expected,
            result: result.fields
          )
        ),
        supportedFields: supported,
        falseClearFields: falseClears,
        reviewRecommended: result.fields.warnings.contains(.reviewRecommended)
      )
    }
  }

  private struct PrivateSplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
      state = seed
    }

    mutating func nextIndex(upperBound: Int) -> Int {
      state &+= 0x9E37_79B9_7F4A_7C15
      var value = state
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      value ^= value >> 31
      return Int(value % UInt64(upperBound))
    }
  }
#endif
