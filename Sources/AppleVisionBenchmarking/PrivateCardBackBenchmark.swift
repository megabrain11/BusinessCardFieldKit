import AppleVisionAdapter
import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  /// External-only manifest for transient real-photo card-back evaluation.
  public struct PrivateCardBackManifest: Decodable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var cases: [PrivateCardBackCase]

    public init(data: Data) throws {
      self = try JSONDecoder().decode(Self.self, from: data)
      guard schemaVersion == Self.currentSchemaVersion else {
        throw CardBackBenchmarkError.unsupportedSchemaVersion
      }
      guard !cases.isEmpty else { throw CardBackBenchmarkError.emptyCorpus }
    }

    func validatedCases(root: URL) throws -> [ValidatedPrivateCardBackCase] {
      let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
      let rootPrefix =
        resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
      let knownFields = Set(CardField.allCases.map(\.rawValue))
      var references = Set<String>()

      return try cases.map { record in
        guard !record.image.isEmpty, !record.image.hasPrefix("/") else {
          throw CardBackBenchmarkError.invalidImageReference
        }
        let components = record.image.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("."), !components.contains("")
        else { throw CardBackBenchmarkError.invalidImageReference }
        guard references.insert(record.image).inserted else {
          throw CardBackBenchmarkError.duplicateImageReference
        }

        let imageURL = resolvedRoot.appendingPathComponent(record.image)
          .standardizedFileURL.resolvingSymlinksInPath()
        guard imageURL.path.hasPrefix(rootPrefix) else {
          throw CardBackBenchmarkError.imageOutsideCorpusRoot
        }
        guard imageURL.isFileURL,
          (try? imageURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else { throw CardBackBenchmarkError.imageUnavailable }

        let expectedKeys = Set(record.backExpected.keys)
          .union(record.front.map { Set($0.keys) } ?? [])
          .union(record.mergedExpected.keys)
        guard expectedKeys.isSubset(of: knownFields) else {
          throw CardBackBenchmarkError.unknownExpectedField
        }
        return ValidatedPrivateCardBackCase(record: record, imageURL: imageURL)
      }.sorted { $0.record.image < $1.record.image }
    }
  }

  public struct PrivateCardBackCase: Decodable, Sendable {
    public var image: String
    public var expectedPayloadKinds: [AppleVisionDetectedBarcode.PayloadKind]
    public var backExpected: [String: [String]]
    public var front: [String: [String]]?
    public var mergedExpected: [String: [String]]
    public var reviewExpected: Bool
    public var recognitionLanguages: [String]?
    public var automaticallyDetectsLanguage: Bool?
    public var attemptsCardIsolation: Bool?
  }

  public enum PrivateCardBackStatus: String, Codable, Sendable {
    case completed
    case skipped
  }

  public enum PrivateCardBackSkipReason: String, Codable, Sendable {
    case privateCorpusUnavailable
  }

  /// Redacted command envelope. Neither branch contains corpus paths or source identities.
  public struct PrivateCardBackCommandReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var reportSchemaVersion: Int
    public var status: PrivateCardBackStatus
    public var skipReason: PrivateCardBackSkipReason?
    public var report: CardBackBenchmarkReport?
    public var maskingComparison: CardBackMaskingStrategyComparison?

    public static var skipped: Self {
      Self(
        reportSchemaVersion: currentSchemaVersion,
        status: .skipped,
        skipReason: .privateCorpusUnavailable,
        report: nil,
        maskingComparison: nil
      )
    }

    public static func completed(_ report: CardBackBenchmarkReport) -> Self {
      Self(
        reportSchemaVersion: currentSchemaVersion,
        status: .completed,
        skipReason: nil,
        report: report,
        maskingComparison: nil
      )
    }

    public static func completedMaskingComparison(
      _ comparison: CardBackMaskingStrategyComparison
    ) -> Self {
      Self(
        reportSchemaVersion: currentSchemaVersion,
        status: .completed,
        skipReason: nil,
        report: nil,
        maskingComparison: comparison
      )
    }
  }

  struct ValidatedPrivateCardBackCase: Sendable {
    var record: PrivateCardBackCase
    var imageURL: URL
  }

  /// Reads private images transiently and returns only aggregate metrics.
  public struct PrivateCardBackBenchmarkRunner: Sendable {
    public var warmupRuns: Int
    public var measuredRuns: Int

    public init(warmupRuns: Int = 1, measuredRuns: Int = 3) {
      self.warmupRuns = warmupRuns
      self.measuredRuns = measuredRuns
    }

    public func run(
      manifest: PrivateCardBackManifest,
      root: URL
    ) throws -> CardBackBenchmarkReport {
      guard warmupRuns >= 0, measuredRuns >= 3 else {
        throw CardBackBenchmarkError.invalidRunCount
      }
      let records = try manifest.validatedCases(root: root)
      for _ in 0..<warmupRuns {
        for record in records { _ = try scan(record) }
      }

      var samples: [CardBackBenchmarkSample] = []
      for _ in 0..<measuredRuns {
        for record in records { samples.append(try scan(record)) }
      }
      return CardBackBenchmarkAggregator.report(
        corpusSchemaVersion: manifest.schemaVersion,
        corpusVersion: nil,
        caseCount: records.count,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        assessment: .privateAggregateAvailable,
        samples: samples
      )
    }

    /// Compares the default and projective masking strategies without exposing private inputs.
    public func runMaskingExperiment(
      manifest: PrivateCardBackManifest,
      root: URL
    ) throws -> CardBackMaskingStrategyComparison {
      guard warmupRuns >= 0, measuredRuns >= 3 else {
        throw CardBackBenchmarkError.invalidRunCount
      }
      let records = try manifest.validatedCases(root: root)
      for repeatIndex in 0..<warmupRuns {
        for (caseIndex, record) in records.enumerated() {
          _ = try maskingPair(
            record,
            baselineFirst: (repeatIndex + caseIndex).isMultiple(of: 2)
          )
        }
      }

      var pairs: [CardBackMaskingStrategyPair] = []
      for repeatIndex in 0..<measuredRuns {
        for (caseIndex, record) in records.enumerated() {
          pairs.append(
            try maskingPair(
              record,
              baselineFirst: (repeatIndex + caseIndex).isMultiple(of: 2)
            )
          )
        }
      }
      return CardBackMaskingStrategyAggregator.report(
        corpusSchemaVersion: manifest.schemaVersion,
        corpusVersion: nil,
        caseCount: records.count,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        pairs: pairs,
        assessment: .privateAggregateAvailable,
        limitations: [
          "Aggregate private evidence omits source identity and per-case outcomes.",
          "Timing varies with hardware, system load, and Vision runtime.",
          "Private aggregate evidence does not replace physical-device human acceptance.",
          "The experiment remains opt-in and does not approve a production default change.",
        ]
      )
    }

    private func scan(_ validated: ValidatedPrivateCardBackCase) throws
      -> CardBackBenchmarkSample
    {
      let record = validated.record
      let data = try Data(contentsOf: validated.imageURL)
      let measurement = try measurement(
        record: record,
        imageData: data,
        maskingStrategy: .rectifiedRedetection
      )
      return CardBackBenchmarkRunner.sample(
        detected: measurement.result,
        expectedPayloadKinds: record.expectedPayloadKinds,
        backExpected: record.backExpected,
        front: record.front ?? [:],
        mergedExpected: record.mergedExpected,
        reviewExpected: record.reviewExpected,
        attemptsCardIsolation: record.attemptsCardIsolation ?? true,
        durationMilliseconds: measurement.durationMilliseconds,
        tags: []
      )
    }

    private func maskingPair(
      _ validated: ValidatedPrivateCardBackCase,
      baselineFirst: Bool
    ) throws -> CardBackMaskingStrategyPair {
      let data = try Data(contentsOf: validated.imageURL)
      let record = validated.record
      let baseline: CardBackMaskingStrategyMeasurement
      let experimental: CardBackMaskingStrategyMeasurement
      if baselineFirst {
        baseline = try measurement(
          record: record,
          imageData: data,
          maskingStrategy: .rectifiedRedetection
        )
        experimental = try measurement(
          record: record,
          imageData: data,
          maskingStrategy: .projectiveSourceObservation
        )
      } else {
        experimental = try measurement(
          record: record,
          imageData: data,
          maskingStrategy: .projectiveSourceObservation
        )
        baseline = try measurement(
          record: record,
          imageData: data,
          maskingStrategy: .rectifiedRedetection
        )
      }
      return CardBackMaskingStrategyPair(
        baseline: baseline,
        experimental: experimental
      )
    }

    private func measurement(
      record: PrivateCardBackCase,
      imageData: Data,
      maskingStrategy: AppleVisionBarcodeMaskingStrategy
    ) throws -> CardBackMaskingStrategyMeasurement {
      var configuration = AppleVisionScanConfiguration(
        recognitionLanguages: record.recognitionLanguages ?? ["ko-KR", "en-US"],
        automaticallyDetectsLanguage: record.automaticallyDetectsLanguage ?? true,
        cardRegion: AppleVisionCardRegionConfiguration(
          mode: (record.attemptsCardIsolation ?? true) ? .automatic : .disabled
        ),
        barcodeMaskingStrategy: maskingStrategy
      )
      configuration.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
      let start = ContinuousClock.now
      let result = try CardBackScanner(configuration: configuration).scan(imageData: imageData)
      let duration = milliseconds(start.duration(to: .now))
      return CardBackMaskingStrategyMeasurement(
        result: result,
        durationMilliseconds: duration
      )
    }

    private func milliseconds(_ duration: Duration) -> Double {
      let components = duration.components
      return Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
    }
  }
#endif
