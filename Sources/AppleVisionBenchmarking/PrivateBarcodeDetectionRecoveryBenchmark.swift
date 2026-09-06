import AppleVisionAdapter
import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  public enum PrivateBarcodeRecoveryGateAssessment: String, Codable, Sendable {
    case insufficientEvidence
    case criteriaNotMet
    case eligibleForHumanReview
  }

  public struct PrivateBarcodeRecoveryGate: Codable, Equatable, Sendable {
    public var assessment: PrivateBarcodeRecoveryGateAssessment
    public var minimumRecoveredDistinctCases: Int
    public var maximumP95DurationDeltaMilliseconds: Double
    public var enoughBaselineFailureDiversity: Bool
    public var hasBaselineSuccessEvidence: Bool
    public var noDetectionRegression: Bool
    public var baselineDetectionPreserved: Bool
    public var noFieldRegression: Bool
    public var latencyWithinBudget: Bool

    static func assess(
      recoveredDistinctCases: Int,
      baselineFailureDistinctCases: Int,
      baselineSuccessDistinctCases: Int,
      detectionRegressionCount: Int,
      baselineDetectionPreserved: Bool,
      fieldRegressionCount: Int,
      p95DurationDeltaMilliseconds: Double,
      maximumP95DurationDeltaMilliseconds: Double
    ) -> Self {
      let minimumRecoveredDistinctCases = 4
      let enoughFailures = baselineFailureDistinctCases >= minimumRecoveredDistinctCases
      let hasBaselineSuccess = baselineSuccessDistinctCases > 0
      let noDetectionRegression = detectionRegressionCount == 0
      let noFieldRegression = fieldRegressionCount == 0
      let latencyWithinBudget =
        p95DurationDeltaMilliseconds <= maximumP95DurationDeltaMilliseconds
      let assessment: PrivateBarcodeRecoveryGateAssessment
      if !enoughFailures || !hasBaselineSuccess {
        assessment = .insufficientEvidence
      } else if noDetectionRegression && baselineDetectionPreserved && noFieldRegression
        && recoveredDistinctCases >= minimumRecoveredDistinctCases && latencyWithinBudget
      {
        assessment = .eligibleForHumanReview
      } else {
        assessment = .criteriaNotMet
      }
      return Self(
        assessment: assessment,
        minimumRecoveredDistinctCases: minimumRecoveredDistinctCases,
        maximumP95DurationDeltaMilliseconds: maximumP95DurationDeltaMilliseconds,
        enoughBaselineFailureDiversity: enoughFailures,
        hasBaselineSuccessEvidence: hasBaselineSuccess,
        noDetectionRegression: noDetectionRegression,
        baselineDetectionPreserved: baselineDetectionPreserved,
        noFieldRegression: noFieldRegression,
        latencyWithinBudget: latencyWithinBudget
      )
    }
  }

  /// Aggregate-only evidence from paired private source-barcode recovery scans.
  public struct PrivateBarcodeDetectionRecoveryComparison: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var reportSchemaVersion: Int
    public var corpusSchemaVersion: Int
    public var caseCount: Int
    public var barcodeTruthCaseCount: Int
    public var detectionOnlyCaseCount: Int
    public var fieldTruthCaseCount: Int
    public var warmupRuns: Int
    public var measuredRuns: Int
    public var measuredPairCount: Int
    public var baselineDetectionRate: Double
    public var experimentalDetectionRate: Double
    public var detectionOnlyBaselineDetectionRate: Double?
    public var detectionOnlyExperimentalDetectionRate: Double?
    public var baselineBarcodeExactRate: Double?
    public var experimentalBarcodeExactRate: Double?
    public var baselineFieldExactRate: Double?
    public var experimentalFieldExactRate: Double?
    public var recoveredSampleCount: Int
    public var recoveredDistinctCaseCount: Int
    public var regressedSampleCount: Int
    public var regressedDistinctCaseCount: Int
    public var baselineFailureDistinctCaseCount: Int
    public var baselineSuccessDistinctCaseCount: Int
    public var baselineDetectionPreservationRate: Double?
    public var baselineBarcodeExactPreservationRate: Double?
    public var fieldParityRate: Double
    public var baselineFieldPreservationRate: Double
    public var fieldRegressionSampleCount: Int
    public var fieldTruthExactRegressionSampleCount: Int
    public var tokenParityRate: Double
    public var cardRegionParityRate: Double
    public var recoveryExecutedSampleCount: Int
    public var baselineSourceBarcodeRequests: BenchmarkDistribution
    public var experimentalSourceBarcodeRequests: BenchmarkDistribution
    public var extraSourceBarcodeRequests: BenchmarkDistribution
    public var baselineDurationMilliseconds: BenchmarkDistribution
    public var experimentalDurationMilliseconds: BenchmarkDistribution
    public var durationDeltaMilliseconds: SignedBenchmarkDistribution
    public var gate: PrivateBarcodeRecoveryGate
    public var evidenceLimitations: [String]
  }

  extension PrivateCardBackBenchmarkRunner {
    /// Runs the shipped path against a default-off recovery configuration in alternating order.
    public func runBarcodeDetectionRecoveryExperiment(
      manifest: PrivateCardBackManifest,
      root: URL,
      maximumP95DurationDeltaMilliseconds: Double = 250
    ) throws -> PrivateBarcodeDetectionRecoveryComparison {
      guard warmupRuns >= 0, measuredRuns >= 3,
        maximumP95DurationDeltaMilliseconds.isFinite,
        maximumP95DurationDeltaMilliseconds >= 0
      else { throw CardBackBenchmarkError.invalidRunCount }
      let records = try manifest.validatedCases(root: root)

      for repeatIndex in 0..<warmupRuns {
        for (caseIndex, record) in records.enumerated() {
          _ = try barcodeRecoveryPair(
            record,
            caseIndex: caseIndex,
            baselineFirst: (repeatIndex + caseIndex).isMultiple(of: 2)
          )
        }
      }

      var pairs: [PrivateBarcodeRecoveryPair] = []
      for repeatIndex in 0..<measuredRuns {
        for (caseIndex, record) in records.enumerated() {
          pairs.append(
            try barcodeRecoveryPair(
              record,
              caseIndex: caseIndex,
              baselineFirst: (repeatIndex + caseIndex).isMultiple(of: 2)
            )
          )
        }
      }
      return PrivateBarcodeRecoveryAggregator.report(
        manifest: manifest,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        maximumP95DurationDeltaMilliseconds: maximumP95DurationDeltaMilliseconds,
        pairs: pairs
      )
    }

    private func barcodeRecoveryPair(
      _ validated: ValidatedPrivateCardBackCase,
      caseIndex: Int,
      baselineFirst: Bool
    ) throws -> PrivateBarcodeRecoveryPair {
      let data = try Data(contentsOf: validated.imageURL)
      let baseline: PrivateBarcodeRecoveryMeasurement
      let experimental: PrivateBarcodeRecoveryMeasurement
      if baselineFirst {
        baseline = try barcodeRecoveryMeasurement(validated.record, imageData: data)
        experimental = try barcodeRecoveryMeasurement(
          validated.record,
          imageData: data,
          recoveryEnabled: true
        )
      } else {
        experimental = try barcodeRecoveryMeasurement(
          validated.record,
          imageData: data,
          recoveryEnabled: true
        )
        baseline = try barcodeRecoveryMeasurement(validated.record, imageData: data)
      }
      return PrivateBarcodeRecoveryPair(
        caseIndex: caseIndex,
        hasBarcodeTruth: validated.record.hasBarcodeTruth,
        hasFieldTruth: validated.record.hasFieldTruth,
        baseline: baseline,
        experimental: experimental
      )
    }

    private func barcodeRecoveryMeasurement(
      _ record: PrivateCardBackCase,
      imageData: Data,
      recoveryEnabled: Bool = false
    ) throws -> PrivateBarcodeRecoveryMeasurement {
      var configuration = AppleVisionScanConfiguration(
        recognitionLanguages: record.recognitionLanguages ?? ["ko-KR", "en-US"],
        automaticallyDetectsLanguage: record.automaticallyDetectsLanguage ?? true,
        cardRegion: AppleVisionCardRegionConfiguration(
          mode: (record.attemptsCardIsolation ?? true) ? .automatic : .disabled
        ),
        diagnostics: AppleVisionDiagnosticsOptions(isEnabled: true),
        barcodeDetectionRecovery: AppleVisionBarcodeDetectionRecoveryOptions(
          isEnabled: recoveryEnabled
        )
      )
      configuration.barcodeMaskingStrategy = .rectifiedRedetection
      let start = ContinuousClock.now
      let result = try CardBackScanner(configuration: configuration).scan(imageData: imageData)
      let components = start.duration(to: .now).components
      let duration =
        Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
      let sample = CardBackBenchmarkRunner.sample(
        detected: result,
        expectedPayloadKinds: record.expectedPayloadKinds,
        backExpected: record.backExpected,
        front: record.front ?? [:],
        mergedExpected: record.mergedExpected,
        reviewExpected: record.reviewExpected,
        attemptsCardIsolation: record.attemptsCardIsolation ?? true,
        durationMilliseconds: duration,
        tags: []
      )
      return PrivateBarcodeRecoveryMeasurement(
        result: result,
        durationMilliseconds: duration,
        barcodeExact: sample.payloadKindsExact,
        fieldExact: sample.backFieldsExact && sample.mergedFieldsExact
      )
    }
  }

  private struct PrivateBarcodeRecoveryMeasurement: Sendable {
    var result: AppleVisionBackScanResult
    var durationMilliseconds: Double
    var barcodeExact: Bool
    var fieldExact: Bool
  }

  private struct PrivateBarcodeRecoveryPair: Sendable {
    var caseIndex: Int
    var hasBarcodeTruth: Bool
    var hasFieldTruth: Bool
    var baseline: PrivateBarcodeRecoveryMeasurement
    var experimental: PrivateBarcodeRecoveryMeasurement
  }

  private enum PrivateBarcodeRecoveryAggregator {
    static func report(
      manifest: PrivateCardBackManifest,
      warmupRuns: Int,
      measuredRuns: Int,
      maximumP95DurationDeltaMilliseconds: Double,
      pairs: [PrivateBarcodeRecoveryPair]
    ) -> PrivateBarcodeDetectionRecoveryComparison {
      let baselineDetected = pairs.map { !$0.baseline.result.detectedBarcodes.isEmpty }
      let experimentalDetected = pairs.map { !$0.experimental.result.detectedBarcodes.isEmpty }
      let recovered = pairs.filter {
        $0.baseline.result.detectedBarcodes.isEmpty
          && !$0.experimental.result.detectedBarcodes.isEmpty
      }
      let regressed = pairs.filter {
        !$0.baseline.result.detectedBarcodes.isEmpty
          && $0.experimental.result.detectedBarcodes.isEmpty
      }
      let baselineFailures = Set(
        pairs.filter { $0.baseline.result.detectedBarcodes.isEmpty }.map(\.caseIndex)
      )
      let baselineSuccesses = Set(
        pairs.filter { !$0.baseline.result.detectedBarcodes.isEmpty }.map(\.caseIndex)
      )
      let baselineSuccessfulPairs = pairs.filter {
        !$0.baseline.result.detectedBarcodes.isEmpty
      }
      let barcodeTruthPairs = pairs.filter(\.hasBarcodeTruth)
      let fieldTruthPairs = pairs.filter(\.hasFieldTruth)
      let detectionOnlyPairs = pairs.filter { !$0.hasBarcodeTruth }
      let fieldPreservation = pairs.map {
        preservesFields(
          baseline: $0.baseline.result.fields, experimental: $0.experimental.result.fields)
      }
      let baselineRequests = pairs.map {
        Double($0.baseline.result.diagnostics?.sourceBarcodeRequestCount ?? 0)
      }
      let experimentalRequests = pairs.map {
        Double($0.experimental.result.diagnostics?.sourceBarcodeRequestCount ?? 0)
      }
      let durationDeltas = pairs.map {
        $0.experimental.durationMilliseconds - $0.baseline.durationMilliseconds
      }
      let durationDelta = SignedBenchmarkDistribution(values: durationDeltas)
      let baselineExactPairs = barcodeTruthPairs.filter(\.baseline.barcodeExact)
      let baselineFieldExactPairs = fieldTruthPairs.filter(\.baseline.fieldExact)
      let detectionPreserved =
        !baselineSuccessfulPairs.isEmpty
        && baselineSuccessfulPairs.allSatisfy {
          !$0.experimental.result.detectedBarcodes.isEmpty
        }
      let recoveredCases = Set(recovered.map(\.caseIndex)).count
      let fieldRegressionCount = fieldPreservation.filter { !$0 }.count
      let gate = PrivateBarcodeRecoveryGate.assess(
        recoveredDistinctCases: recoveredCases,
        baselineFailureDistinctCases: baselineFailures.count,
        baselineSuccessDistinctCases: baselineSuccesses.count,
        detectionRegressionCount: regressed.count,
        baselineDetectionPreserved: detectionPreserved,
        fieldRegressionCount: fieldRegressionCount,
        p95DurationDeltaMilliseconds: durationDelta.p95,
        maximumP95DurationDeltaMilliseconds: maximumP95DurationDeltaMilliseconds
      )

      return PrivateBarcodeDetectionRecoveryComparison(
        reportSchemaVersion: PrivateBarcodeDetectionRecoveryComparison.currentSchemaVersion,
        corpusSchemaVersion: manifest.schemaVersion,
        caseCount: manifest.cases.count,
        barcodeTruthCaseCount: manifest.cases.filter(\.hasBarcodeTruth).count,
        detectionOnlyCaseCount: manifest.cases.filter { !$0.hasBarcodeTruth }.count,
        fieldTruthCaseCount: manifest.cases.filter(\.hasFieldTruth).count,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        measuredPairCount: pairs.count,
        baselineDetectionRate: rate(baselineDetected),
        experimentalDetectionRate: rate(experimentalDetected),
        detectionOnlyBaselineDetectionRate: optionalRate(
          detectionOnlyPairs.map { !$0.baseline.result.detectedBarcodes.isEmpty }
        ),
        detectionOnlyExperimentalDetectionRate: optionalRate(
          detectionOnlyPairs.map { !$0.experimental.result.detectedBarcodes.isEmpty }
        ),
        baselineBarcodeExactRate: optionalRate(barcodeTruthPairs.map(\.baseline.barcodeExact)),
        experimentalBarcodeExactRate: optionalRate(
          barcodeTruthPairs.map(\.experimental.barcodeExact)
        ),
        baselineFieldExactRate: optionalRate(fieldTruthPairs.map(\.baseline.fieldExact)),
        experimentalFieldExactRate: optionalRate(fieldTruthPairs.map(\.experimental.fieldExact)),
        recoveredSampleCount: recovered.count,
        recoveredDistinctCaseCount: recoveredCases,
        regressedSampleCount: regressed.count,
        regressedDistinctCaseCount: Set(regressed.map(\.caseIndex)).count,
        baselineFailureDistinctCaseCount: baselineFailures.count,
        baselineSuccessDistinctCaseCount: baselineSuccesses.count,
        baselineDetectionPreservationRate: optionalRate(
          baselineSuccessfulPairs.map { !$0.experimental.result.detectedBarcodes.isEmpty }
        ),
        baselineBarcodeExactPreservationRate: optionalRate(
          baselineExactPairs.map(\.experimental.barcodeExact)
        ),
        fieldParityRate: rate(
          pairs.map { $0.baseline.result.fields == $0.experimental.result.fields }
        ),
        baselineFieldPreservationRate: rate(fieldPreservation),
        fieldRegressionSampleCount: fieldRegressionCount,
        fieldTruthExactRegressionSampleCount: baselineFieldExactPairs.filter {
          !$0.experimental.fieldExact
        }.count,
        tokenParityRate: rate(
          pairs.map { $0.baseline.result.tokens == $0.experimental.result.tokens }
        ),
        cardRegionParityRate: rate(
          pairs.map {
            $0.baseline.result.cardRegionSelection == $0.experimental.result.cardRegionSelection
          }
        ),
        recoveryExecutedSampleCount: pairs.filter {
          $0.experimental.result.diagnostics?.sourceBarcodeRecoveryExecuted == true
        }.count,
        baselineSourceBarcodeRequests: BenchmarkDistribution(values: baselineRequests),
        experimentalSourceBarcodeRequests: BenchmarkDistribution(values: experimentalRequests),
        extraSourceBarcodeRequests: BenchmarkDistribution(
          values: zip(baselineRequests, experimentalRequests).map { $1 - $0 }
        ),
        baselineDurationMilliseconds: BenchmarkDistribution(
          values: pairs.map(\.baseline.durationMilliseconds)
        ),
        experimentalDurationMilliseconds: BenchmarkDistribution(
          values: pairs.map(\.experimental.durationMilliseconds)
        ),
        durationDeltaMilliseconds: durationDelta,
        gate: gate,
        evidenceLimitations: [
          "Aggregate private evidence omits source identity and per-case outcomes.",
          "Detection-only cases cannot establish decoded payload correctness.",
          "Timing varies with device, system load, and Vision runtime.",
          "An eligible gate permits human review only and never changes the shipped default.",
        ]
      )
    }

    private static func preservesFields(
      baseline: CardFieldResult,
      experimental: CardFieldResult
    ) -> Bool {
      CardField.allCases.allSatisfy { field in
        let expected = Set(baseline.values(for: field).map(\.normalizedValue))
        let observed = Set(experimental.values(for: field).map(\.normalizedValue))
        return expected.isSubset(of: observed)
      }
    }

    private static func rate(_ values: [Bool]) -> Double {
      guard !values.isEmpty else { return 0 }
      return Double(values.filter { $0 }.count) / Double(values.count)
    }

    private static func optionalRate(_ values: [Bool]) -> Double? {
      values.isEmpty ? nil : rate(values)
    }
  }
#endif
