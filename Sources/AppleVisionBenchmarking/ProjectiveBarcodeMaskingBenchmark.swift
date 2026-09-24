import AppleVisionAdapter
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics

  /// A percentile distribution that preserves signed deltas such as latency changes.
  public struct SignedBenchmarkDistribution: Codable, Equatable, Sendable {
    public var sampleCount: Int
    public var p50: Double
    public var p95: Double

    public init(values: [Double]) {
      let sorted = values.map { $0.isFinite ? $0 : 0 }.sorted()
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

  /// Aggregate-only paired evidence for the opt-in source-observation masking experiment.
  public struct CardBackMaskingStrategyComparison: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var reportSchemaVersion: Int
    public var corpusSchemaVersion: Int
    public var corpusVersion: String?
    public var caseCount: Int
    public var warmupRuns: Int
    public var measuredRuns: Int
    public var baselineStrategy: AppleVisionBarcodeMaskingStrategy
    public var experimentalStrategy: AppleVisionBarcodeMaskingStrategy
    public var resultParityRate: Double
    public var tokenParityRate: Double
    public var fieldParityRate: Double
    public var barcodeParityRate: Double
    public var cardRegionParityRate: Double
    public var baselineTotalBarcodeRequests: BenchmarkDistribution
    public var experimentalTotalBarcodeRequests: BenchmarkDistribution
    public var barcodeRequestReduction: BenchmarkDistribution
    public var baselineDurationMilliseconds: BenchmarkDistribution
    public var experimentalDurationMilliseconds: BenchmarkDistribution
    public var durationDeltaMilliseconds: SignedBenchmarkDistribution
    public var isolatedBaselineDurationMilliseconds: BenchmarkDistribution
    public var isolatedExperimentalDurationMilliseconds: BenchmarkDistribution
    public var isolatedDurationDeltaMilliseconds: SignedBenchmarkDistribution
    public var isolatedBarcodeRequestReduction: BenchmarkDistribution
    public var projectiveMaskingAppliedSampleCount: Int
    public var projectiveMaskFallbackCount: Int
    public var isolatedSampleCount: Int
    public var evidenceAssessment: CardBackEvidenceAssessment
    public var evidenceLimitations: [String]

    init(
      corpusSchemaVersion: Int,
      corpusVersion: String?,
      caseCount: Int,
      warmupRuns: Int,
      measuredRuns: Int,
      resultParityRate: Double,
      tokenParityRate: Double,
      fieldParityRate: Double,
      barcodeParityRate: Double,
      cardRegionParityRate: Double,
      baselineTotalBarcodeRequests: BenchmarkDistribution,
      experimentalTotalBarcodeRequests: BenchmarkDistribution,
      barcodeRequestReduction: BenchmarkDistribution,
      baselineDurationMilliseconds: BenchmarkDistribution,
      experimentalDurationMilliseconds: BenchmarkDistribution,
      durationDeltaMilliseconds: SignedBenchmarkDistribution,
      isolatedBaselineDurationMilliseconds: BenchmarkDistribution,
      isolatedExperimentalDurationMilliseconds: BenchmarkDistribution,
      isolatedDurationDeltaMilliseconds: SignedBenchmarkDistribution,
      isolatedBarcodeRequestReduction: BenchmarkDistribution,
      projectiveMaskingAppliedSampleCount: Int,
      projectiveMaskFallbackCount: Int,
      isolatedSampleCount: Int,
      evidenceAssessment: CardBackEvidenceAssessment,
      evidenceLimitations: [String]
    ) {
      reportSchemaVersion = Self.currentSchemaVersion
      self.corpusSchemaVersion = corpusSchemaVersion
      self.corpusVersion = corpusVersion
      self.caseCount = max(caseCount, 0)
      self.warmupRuns = max(warmupRuns, 0)
      self.measuredRuns = max(measuredRuns, 0)
      baselineStrategy = .rectifiedRedetection
      experimentalStrategy = .projectiveSourceObservation
      self.resultParityRate = max(min(resultParityRate, 1), 0)
      self.tokenParityRate = max(min(tokenParityRate, 1), 0)
      self.fieldParityRate = max(min(fieldParityRate, 1), 0)
      self.barcodeParityRate = max(min(barcodeParityRate, 1), 0)
      self.cardRegionParityRate = max(min(cardRegionParityRate, 1), 0)
      self.baselineTotalBarcodeRequests = baselineTotalBarcodeRequests
      self.experimentalTotalBarcodeRequests = experimentalTotalBarcodeRequests
      self.barcodeRequestReduction = barcodeRequestReduction
      self.baselineDurationMilliseconds = baselineDurationMilliseconds
      self.experimentalDurationMilliseconds = experimentalDurationMilliseconds
      self.durationDeltaMilliseconds = durationDeltaMilliseconds
      self.isolatedBaselineDurationMilliseconds = isolatedBaselineDurationMilliseconds
      self.isolatedExperimentalDurationMilliseconds = isolatedExperimentalDurationMilliseconds
      self.isolatedDurationDeltaMilliseconds = isolatedDurationDeltaMilliseconds
      self.isolatedBarcodeRequestReduction = isolatedBarcodeRequestReduction
      self.projectiveMaskingAppliedSampleCount = max(projectiveMaskingAppliedSampleCount, 0)
      self.projectiveMaskFallbackCount = max(projectiveMaskFallbackCount, 0)
      self.isolatedSampleCount = max(isolatedSampleCount, 0)
      self.evidenceAssessment = evidenceAssessment
      self.evidenceLimitations = evidenceLimitations
    }
  }

  public struct CardBackMaskingStrategyBenchmarkRunner: Sendable {
    public var warmupRuns: Int
    public var measuredRuns: Int

    public init(warmupRuns: Int = 1, measuredRuns: Int = 5) {
      self.warmupRuns = warmupRuns
      self.measuredRuns = measuredRuns
    }

    public func run(
      manifest: CardBackCorpusManifest
    ) throws -> CardBackMaskingStrategyComparison {
      guard warmupRuns >= 0, measuredRuns > 0 else {
        throw CardBackBenchmarkError.invalidRunCount
      }
      let baseline = CardBackBenchmarkRunner(
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns
      )
      for repeatIndex in 0..<warmupRuns {
        for (caseIndex, record) in manifest.cases.enumerated() {
          let image = try CardBackSceneRenderer.render(record)
          if (repeatIndex + caseIndex).isMultiple(of: 2) {
            _ = try baseline.scanResult(
              record, image: image, maskingStrategy: .rectifiedRedetection
            )
            _ = try baseline.scanResult(
              record, image: image, maskingStrategy: .projectiveSourceObservation
            )
          } else {
            _ = try baseline.scanResult(
              record, image: image, maskingStrategy: .projectiveSourceObservation
            )
            _ = try baseline.scanResult(
              record, image: image, maskingStrategy: .rectifiedRedetection
            )
          }
        }
      }

      var pairs: [CardBackMaskingStrategyPair] = []
      for repeatIndex in 0..<measuredRuns {
        for (caseIndex, record) in manifest.cases.enumerated() {
          let image = try CardBackSceneRenderer.render(record)
          let shipped:
            (
              result: AppleVisionBackScanResult,
              durationMilliseconds: Double,
              attemptsIsolation: Bool
            )
          let experimental:
            (
              result: AppleVisionBackScanResult,
              durationMilliseconds: Double,
              attemptsIsolation: Bool
            )
          if (repeatIndex + caseIndex).isMultiple(of: 2) {
            shipped = try baseline.scanResult(
              record, image: image, maskingStrategy: .rectifiedRedetection
            )
            experimental = try baseline.scanResult(
              record, image: image, maskingStrategy: .projectiveSourceObservation
            )
          } else {
            experimental = try baseline.scanResult(
              record, image: image, maskingStrategy: .projectiveSourceObservation
            )
            shipped = try baseline.scanResult(
              record, image: image, maskingStrategy: .rectifiedRedetection
            )
          }
          pairs.append(
            CardBackMaskingStrategyPair(
              baseline: CardBackMaskingStrategyMeasurement(
                result: shipped.result,
                durationMilliseconds: shipped.durationMilliseconds
              ),
              experimental: CardBackMaskingStrategyMeasurement(
                result: experimental.result,
                durationMilliseconds: experimental.durationMilliseconds
              )
            )
          )
        }
      }
      return CardBackMaskingStrategyAggregator.report(
        corpusSchemaVersion: manifest.schemaVersion,
        corpusVersion: manifest.corpusVersion,
        caseCount: manifest.cases.count,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        pairs: pairs,
        assessment: .syntheticOnly,
        limitations: [
          "Synthetic Core Text scenes do not establish physical-device or real-photo performance.",
          "Timing varies with hardware, system load, and Vision runtime.",
          "The experiment remains opt-in and does not approve a production default change.",
        ]
      )
    }
  }

  struct CardBackMaskingStrategyMeasurement: Sendable {
    var result: AppleVisionBackScanResult
    var durationMilliseconds: Double
  }

  struct CardBackMaskingStrategyPair: Sendable {
    var baseline: CardBackMaskingStrategyMeasurement
    var experimental: CardBackMaskingStrategyMeasurement
  }

  enum CardBackMaskingStrategyAggregator {
    static func report(
      corpusSchemaVersion: Int,
      corpusVersion: String?,
      caseCount: Int,
      warmupRuns: Int,
      measuredRuns: Int,
      pairs: [CardBackMaskingStrategyPair],
      assessment: CardBackEvidenceAssessment,
      limitations: [String]
    ) -> CardBackMaskingStrategyComparison {
      let count = pairs.count
      let baselineResults = pairs.map(\.baseline.result)
      let experimentalResults = pairs.map(\.experimental.result)
      let tokenParity = zip(baselineResults, experimentalResults).map { $0.tokens == $1.tokens }
      let fieldParity = zip(baselineResults, experimentalResults).map { $0.fields == $1.fields }
      let barcodeParity = zip(baselineResults, experimentalResults).map {
        $0.detectedBarcodes == $1.detectedBarcodes
      }
      let cardRegionParity = zip(baselineResults, experimentalResults).map {
        $0.cardRegionSelection == $1.cardRegionSelection
      }
      let resultParity = zip(tokenParity, zip(fieldParity, zip(barcodeParity, cardRegionParity)))
        .map { $0 && $1.0 && $1.1.0 && $1.1.1 }
      let baselineRequests = pairs.map {
        Double($0.baseline.result.diagnostics?.totalBarcodeRequestCount ?? 0)
      }
      let experimentalRequests = pairs.map {
        Double($0.experimental.result.diagnostics?.totalBarcodeRequestCount ?? 0)
      }
      let requestReduction = zip(baselineRequests, experimentalRequests).map(-)
      let baselineDurations = pairs.map { $0.baseline.durationMilliseconds }
      let experimentalDurations = pairs.map { $0.experimental.durationMilliseconds }
      let durationDelta = zip(baselineDurations, experimentalDurations).map { $1 - $0 }
      let isolatedPairs = pairs.filter {
        if case .isolated = $0.experimental.result.cardRegionSelection { return true }
        return false
      }
      let isolatedBaselineDurations = isolatedPairs.map { $0.baseline.durationMilliseconds }
      let isolatedExperimentalDurations = isolatedPairs.map { $0.experimental.durationMilliseconds }
      let isolatedDurationDelta = zip(
        isolatedBaselineDurations,
        isolatedExperimentalDurations
      ).map { $1 - $0 }
      let isolatedRequestReduction = isolatedPairs.map {
        Double($0.baseline.result.diagnostics?.totalBarcodeRequestCount ?? 0)
          - Double($0.experimental.result.diagnostics?.totalBarcodeRequestCount ?? 0)
      }
      let appliedCount = pairs.filter {
        $0.experimental.result.diagnostics?.projectiveMaskingApplied == true
      }.count
      let fallbackCount = pairs.reduce(0) {
        $0 + ($1.experimental.result.diagnostics?.projectiveMaskFallbackCount ?? 0)
      }
      let isolatedCount = pairs.filter {
        if case .isolated = $0.experimental.result.cardRegionSelection { return true }
        return false
      }.count
      return CardBackMaskingStrategyComparison(
        corpusSchemaVersion: corpusSchemaVersion,
        corpusVersion: corpusVersion,
        caseCount: caseCount,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        resultParityRate: rate(resultParity, count),
        tokenParityRate: rate(tokenParity, count),
        fieldParityRate: rate(fieldParity, count),
        barcodeParityRate: rate(barcodeParity, count),
        cardRegionParityRate: rate(cardRegionParity, count),
        baselineTotalBarcodeRequests: BenchmarkDistribution(values: baselineRequests),
        experimentalTotalBarcodeRequests: BenchmarkDistribution(values: experimentalRequests),
        barcodeRequestReduction: BenchmarkDistribution(values: requestReduction),
        baselineDurationMilliseconds: BenchmarkDistribution(values: baselineDurations),
        experimentalDurationMilliseconds: BenchmarkDistribution(values: experimentalDurations),
        durationDeltaMilliseconds: SignedBenchmarkDistribution(values: durationDelta),
        isolatedBaselineDurationMilliseconds: BenchmarkDistribution(
          values: isolatedBaselineDurations
        ),
        isolatedExperimentalDurationMilliseconds: BenchmarkDistribution(
          values: isolatedExperimentalDurations
        ),
        isolatedDurationDeltaMilliseconds: SignedBenchmarkDistribution(
          values: isolatedDurationDelta),
        isolatedBarcodeRequestReduction: BenchmarkDistribution(values: isolatedRequestReduction),
        projectiveMaskingAppliedSampleCount: appliedCount,
        projectiveMaskFallbackCount: fallbackCount,
        isolatedSampleCount: isolatedCount,
        evidenceAssessment: assessment,
        evidenceLimitations: limitations
      )
    }

    private static func rate(_ values: [Bool], _ denominator: Int) -> Double {
      guard denominator > 0 else { return 0 }
      return Double(values.filter { $0 }.count) / Double(denominator)
    }
  }
#endif
