import AppleVisionAdapter
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics

  /// Aggregate-only paired evidence for the default-off source barcode recovery experiment.
  public struct BarcodeDetectionStyleSummary: Codable, Equatable, Sendable {
    public var style: String
    public var sampleCount: Int
    public var baselineBarcodeExactRate: Double
    public var experimentalBarcodeExactRate: Double
    public var recoveredSampleCount: Int
  }

  public struct BarcodeDetectionRecoveryComparison: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var reportSchemaVersion: Int
    public var corpusSchemaVersion: Int
    public var corpusVersion: String
    public var caseCount: Int
    public var warmupRuns: Int
    public var measuredRuns: Int
    public var baselineBarcodeExactRate: Double
    public var experimentalBarcodeExactRate: Double
    public var baselineFieldExactRate: Double
    public var experimentalFieldExactRate: Double
    public var recoveredSampleCount: Int
    public var regressedSampleCount: Int
    public var tokenParityRate: Double
    public var cardRegionParityRate: Double
    public var baselineBarcodeExactPreservationRate: Double
    public var fieldRegressionSampleCount: Int
    public var recoveryExecutedSampleCount: Int
    public var baselineSourceBarcodeRequests: BenchmarkDistribution
    public var experimentalSourceBarcodeRequests: BenchmarkDistribution
    public var extraSourceBarcodeRequests: BenchmarkDistribution
    public var baselineDurationMilliseconds: BenchmarkDistribution
    public var experimentalDurationMilliseconds: BenchmarkDistribution
    public var durationDeltaMilliseconds: SignedBenchmarkDistribution
    public var styleSummaries: [BarcodeDetectionStyleSummary]
    public var evidenceLimitations: [String]
  }

  public struct BarcodeDetectionRecoveryBenchmarkRunner: Sendable {
    public var warmupRuns: Int
    public var measuredRuns: Int

    public init(warmupRuns: Int = 1, measuredRuns: Int = 3) {
      self.warmupRuns = warmupRuns
      self.measuredRuns = measuredRuns
    }

    public func run(
      manifest: CardBackCorpusManifest
    ) throws -> BarcodeDetectionRecoveryComparison {
      guard warmupRuns >= 0, measuredRuns > 0 else {
        throw CardBackBenchmarkError.invalidRunCount
      }
      let runner = CardBackBenchmarkRunner(warmupRuns: 0, measuredRuns: 1)
      let recovery = AppleVisionBarcodeDetectionRecoveryOptions(isEnabled: true)

      for repeatIndex in 0..<warmupRuns {
        for (caseIndex, record) in manifest.cases.enumerated() {
          let image = try CardBackSceneRenderer.render(record)
          if (repeatIndex + caseIndex).isMultiple(of: 2) {
            _ = try runner.scanResult(record, image: image)
            _ = try runner.scanResult(
              record,
              image: image,
              barcodeDetectionRecovery: recovery
            )
          } else {
            _ = try runner.scanResult(
              record,
              image: image,
              barcodeDetectionRecovery: recovery
            )
            _ = try runner.scanResult(record, image: image)
          }
        }
      }

      var pairs: [Pair] = []
      for repeatIndex in 0..<measuredRuns {
        for (caseIndex, record) in manifest.cases.enumerated() {
          let image = try CardBackSceneRenderer.render(record)
          let baseline: Measurement
          let experimental: Measurement
          if (repeatIndex + caseIndex).isMultiple(of: 2) {
            baseline = try measurement(record, image: image, runner: runner)
            experimental = try measurement(
              record,
              image: image,
              runner: runner,
              recovery: recovery
            )
          } else {
            experimental = try measurement(
              record,
              image: image,
              runner: runner,
              recovery: recovery
            )
            baseline = try measurement(record, image: image, runner: runner)
          }
          pairs.append(Pair(baseline: baseline, experimental: experimental))
        }
      }
      return Self.aggregate(
        manifest: manifest,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        pairs: pairs
      )
    }

    private func measurement(
      _ record: CardBackCorpusCase,
      image: CGImage,
      runner: CardBackBenchmarkRunner,
      recovery: AppleVisionBarcodeDetectionRecoveryOptions =
        AppleVisionBarcodeDetectionRecoveryOptions()
    ) throws -> Measurement {
      let measured = try runner.scanResult(
        record,
        image: image,
        barcodeDetectionRecovery: recovery
      )
      let sample = CardBackBenchmarkRunner.sample(
        detected: measured.result,
        expectedPayloadKinds: record.expectedPayloadKinds,
        backExpected: record.backExpected,
        front: record.front ?? [:],
        mergedExpected: record.mergedExpected,
        reviewExpected: record.reviewExpected,
        attemptsCardIsolation: measured.attemptsIsolation,
        durationMilliseconds: measured.durationMilliseconds,
        tags: record.tags
      )
      return Measurement(
        result: measured.result,
        durationMilliseconds: measured.durationMilliseconds,
        barcodeExact: sample.payloadKindsExact,
        fieldsExact: sample.backFieldsExact && sample.mergedFieldsExact
      )
    }

    private static func aggregate(
      manifest: CardBackCorpusManifest,
      warmupRuns: Int,
      measuredRuns: Int,
      pairs: [Pair]
    ) -> BarcodeDetectionRecoveryComparison {
      let baselineBarcodeExact = pairs.filter(\.baseline.barcodeExact).count
      let experimentalBarcodeExact = pairs.filter(\.experimental.barcodeExact).count
      let baselineFieldExact = pairs.filter(\.baseline.fieldsExact).count
      let experimentalFieldExact = pairs.filter(\.experimental.fieldsExact).count
      let preserved = pairs.filter {
        $0.baseline.barcodeExact && $0.experimental.barcodeExact
      }.count
      let baselineRequests = pairs.map {
        Double($0.baseline.result.diagnostics?.sourceBarcodeRequestCount ?? 0)
      }
      let experimentalRequests = pairs.map {
        Double($0.experimental.result.diagnostics?.sourceBarcodeRequestCount ?? 0)
      }
      return BarcodeDetectionRecoveryComparison(
        reportSchemaVersion: BarcodeDetectionRecoveryComparison.currentSchemaVersion,
        corpusSchemaVersion: manifest.schemaVersion,
        corpusVersion: manifest.corpusVersion,
        caseCount: manifest.cases.count,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        baselineBarcodeExactRate: rate(baselineBarcodeExact, pairs.count),
        experimentalBarcodeExactRate: rate(experimentalBarcodeExact, pairs.count),
        baselineFieldExactRate: rate(baselineFieldExact, pairs.count),
        experimentalFieldExactRate: rate(experimentalFieldExact, pairs.count),
        recoveredSampleCount: pairs.filter {
          !$0.baseline.barcodeExact && $0.experimental.barcodeExact
        }.count,
        regressedSampleCount: pairs.filter {
          $0.baseline.barcodeExact && !$0.experimental.barcodeExact
        }.count,
        tokenParityRate: rate(
          pairs.filter { $0.baseline.result.tokens == $0.experimental.result.tokens }.count,
          pairs.count
        ),
        cardRegionParityRate: rate(
          pairs.filter {
            $0.baseline.result.cardRegionSelection
              == $0.experimental.result.cardRegionSelection
          }.count,
          pairs.count
        ),
        baselineBarcodeExactPreservationRate: rate(preserved, baselineBarcodeExact),
        fieldRegressionSampleCount: pairs.filter {
          $0.baseline.fieldsExact && !$0.experimental.fieldsExact
        }.count,
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
        durationDeltaMilliseconds: SignedBenchmarkDistribution(
          values: pairs.map {
            $0.experimental.durationMilliseconds - $0.baseline.durationMilliseconds
          }
        ),
        styleSummaries: styleSummaries(manifest: manifest, pairs: pairs),
        evidenceLimitations: [
          "Synthetic QR stress evidence does not establish real-camera recovery.",
          "Timing varies with hardware, system load, and Vision runtime.",
          "The recovery experiment remains opt-in and does not approve a default change.",
        ]
      )
    }

    private static func styleSummaries(
      manifest: CardBackCorpusManifest,
      pairs: [Pair]
    ) -> [BarcodeDetectionStyleSummary] {
      let caseCount = manifest.cases.count
      guard caseCount > 0 else { return [] }
      let styles = Set(
        manifest.cases.flatMap(\.tags).filter { $0 != "barcode-detection-stress" }
      )
      return styles.sorted().map { style in
        let caseIndices = Set(
          manifest.cases.enumerated().compactMap { index, record in
            record.tags.contains(style) ? index : nil
          }
        )
        let selected = pairs.enumerated().compactMap { index, pair in
          caseIndices.contains(index % caseCount) ? pair : nil
        }
        return BarcodeDetectionStyleSummary(
          style: style,
          sampleCount: selected.count,
          baselineBarcodeExactRate: rate(
            selected.filter(\.baseline.barcodeExact).count,
            selected.count
          ),
          experimentalBarcodeExactRate: rate(
            selected.filter(\.experimental.barcodeExact).count,
            selected.count
          ),
          recoveredSampleCount: selected.filter {
            !$0.baseline.barcodeExact && $0.experimental.barcodeExact
          }.count
        )
      }
    }

    private static func rate(_ numerator: Int, _ denominator: Int) -> Double {
      guard denominator > 0 else { return 0 }
      return Double(numerator) / Double(denominator)
    }

    private struct Measurement {
      var result: AppleVisionBackScanResult
      var durationMilliseconds: Double
      var barcodeExact: Bool
      var fieldsExact: Bool
    }

    private struct Pair {
      var baseline: Measurement
      var experimental: Measurement
    }
  }
#endif
