import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(Vision)
  /// Stable stages for privacy-safe card-back scan diagnostics.
  public enum AppleVisionBackScanStage: String, Codable, CaseIterable, Sendable {
    case sourceBarcodeDetection
    case tokenRecognition
    case isolatedMaskDetection
    case classificationAndMerge
    case total
  }

  /// One card-back stage duration accumulated under a fixed identifier.
  public struct AppleVisionBackStageTiming: Codable, Equatable, Sendable {
    public var stage: AppleVisionBackScanStage
    public var durationMilliseconds: Double

    public init(stage: AppleVisionBackScanStage, durationMilliseconds: Double) {
      self.stage = stage
      self.durationMilliseconds = max(durationMilliseconds, 0)
    }
  }

  /// Opt-in, content-free diagnostics for one completed card-back scan.
  ///
  /// The contract contains only durations, fixed request counts, and one
  /// execution booleans. It never contains payloads, OCR text, image data,
  /// geometry, token values, or paths.
  public struct AppleVisionBackScanDiagnostics: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var stageTimings: [AppleVisionBackStageTiming]
    public var totalBarcodeRequestCount: Int
    public var sourceBarcodeRequestCount: Int
    public var sourceBarcodeRecoveryRequestCount: Int
    public var sourceBarcodeRecoveryExecuted: Bool
    public var isolatedMaskBarcodeRequestCount: Int
    public var isolatedMaskDetectionExecuted: Bool
    public var maskingStrategy: AppleVisionBarcodeMaskingStrategy
    public var projectiveMaskingApplied: Bool
    public var projectiveMaskFallbackCount: Int

    public init(
      schemaVersion: Int = AppleVisionBackScanDiagnostics.currentSchemaVersion,
      stageTimings: [AppleVisionBackStageTiming],
      totalBarcodeRequestCount: Int,
      sourceBarcodeRequestCount: Int,
      sourceBarcodeRecoveryRequestCount: Int = 0,
      sourceBarcodeRecoveryExecuted: Bool = false,
      isolatedMaskBarcodeRequestCount: Int,
      isolatedMaskDetectionExecuted: Bool,
      maskingStrategy: AppleVisionBarcodeMaskingStrategy = .rectifiedRedetection,
      projectiveMaskingApplied: Bool = false,
      projectiveMaskFallbackCount: Int = 0
    ) {
      self.schemaVersion = schemaVersion
      self.stageTimings = stageTimings
      self.totalBarcodeRequestCount = max(totalBarcodeRequestCount, 0)
      self.sourceBarcodeRequestCount = max(sourceBarcodeRequestCount, 0)
      self.sourceBarcodeRecoveryRequestCount = max(sourceBarcodeRecoveryRequestCount, 0)
      self.sourceBarcodeRecoveryExecuted = sourceBarcodeRecoveryExecuted
      self.isolatedMaskBarcodeRequestCount = max(isolatedMaskBarcodeRequestCount, 0)
      self.isolatedMaskDetectionExecuted = isolatedMaskDetectionExecuted
      self.maskingStrategy = maskingStrategy
      self.projectiveMaskingApplied = projectiveMaskingApplied
      self.projectiveMaskFallbackCount = max(projectiveMaskFallbackCount, 0)
    }

    private enum CodingKeys: String, CodingKey {
      case schemaVersion
      case stageTimings
      case totalBarcodeRequestCount
      case sourceBarcodeRequestCount
      case sourceBarcodeRecoveryRequestCount
      case sourceBarcodeRecoveryExecuted
      case isolatedMaskBarcodeRequestCount
      case isolatedMaskDetectionExecuted
      case maskingStrategy
      case projectiveMaskingApplied
      case projectiveMaskFallbackCount
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
        schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
        stageTimings: try container.decode(
          [AppleVisionBackStageTiming].self, forKey: .stageTimings
        ),
        totalBarcodeRequestCount: try container.decode(
          Int.self, forKey: .totalBarcodeRequestCount
        ),
        sourceBarcodeRequestCount: try container.decode(
          Int.self, forKey: .sourceBarcodeRequestCount
        ),
        sourceBarcodeRecoveryRequestCount: try container.decodeIfPresent(
          Int.self, forKey: .sourceBarcodeRecoveryRequestCount
        ) ?? 0,
        sourceBarcodeRecoveryExecuted: try container.decodeIfPresent(
          Bool.self, forKey: .sourceBarcodeRecoveryExecuted
        ) ?? false,
        isolatedMaskBarcodeRequestCount: try container.decode(
          Int.self, forKey: .isolatedMaskBarcodeRequestCount
        ),
        isolatedMaskDetectionExecuted: try container.decode(
          Bool.self, forKey: .isolatedMaskDetectionExecuted
        ),
        maskingStrategy: try container.decodeIfPresent(
          AppleVisionBarcodeMaskingStrategy.self, forKey: .maskingStrategy
        ) ?? .rectifiedRedetection,
        projectiveMaskingApplied: try container.decodeIfPresent(
          Bool.self, forKey: .projectiveMaskingApplied
        ) ?? false,
        projectiveMaskFallbackCount: try container.decodeIfPresent(
          Int.self, forKey: .projectiveMaskFallbackCount
        ) ?? 0
      )
    }
  }

  final class BackScanInstrumentation: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: any AppleVisionDiagnosticsClock
    private let startedAt: Double
    private var durations: [AppleVisionBackScanStage: Double] = [:]
    private var sourceBarcodeRequests = 0
    private var sourceBarcodeRecoveryRequests = 0
    private var isolatedMaskBarcodeRequests = 0
    private let maskingStrategy: AppleVisionBarcodeMaskingStrategy
    private var projectiveMaskingApplied = false
    private var projectiveMaskFallbacks = 0

    init(
      clock: any AppleVisionDiagnosticsClock,
      maskingStrategy: AppleVisionBarcodeMaskingStrategy = .rectifiedRedetection
    ) {
      self.clock = clock
      self.startedAt = clock.nowMilliseconds()
      self.maskingStrategy = maskingStrategy
    }

    func measure<T>(
      _ stage: AppleVisionBackScanStage,
      _ operation: () throws -> T
    ) rethrows -> T {
      let stageStart = clock.nowMilliseconds()
      defer {
        let elapsed = max(clock.nowMilliseconds() - stageStart, 0)
        lock.lock()
        durations[stage, default: 0] += elapsed
        lock.unlock()
      }
      return try operation()
    }

    func recordSourceBarcodeRequest() {
      lock.lock()
      sourceBarcodeRequests += 1
      lock.unlock()
    }

    func recordSourceBarcodeRecoveryRequest() {
      lock.lock()
      sourceBarcodeRequests += 1
      sourceBarcodeRecoveryRequests += 1
      lock.unlock()
    }

    func recordIsolatedMaskBarcodeRequest() {
      lock.lock()
      isolatedMaskBarcodeRequests += 1
      lock.unlock()
    }

    func recordProjectiveMaskApplied() {
      lock.lock()
      projectiveMaskingApplied = true
      lock.unlock()
    }

    func recordProjectiveMaskFallback() {
      lock.lock()
      projectiveMaskFallbacks += 1
      lock.unlock()
    }

    func snapshot() -> AppleVisionBackScanDiagnostics {
      lock.lock()
      defer { lock.unlock() }

      var timings = AppleVisionBackScanStage.allCases.compactMap { stage in
        durations[stage].map {
          AppleVisionBackStageTiming(stage: stage, durationMilliseconds: $0)
        }
      }
      timings.append(
        AppleVisionBackStageTiming(
          stage: .total,
          durationMilliseconds: max(clock.nowMilliseconds() - startedAt, 0)
        )
      )
      return AppleVisionBackScanDiagnostics(
        stageTimings: timings,
        totalBarcodeRequestCount: sourceBarcodeRequests + isolatedMaskBarcodeRequests,
        sourceBarcodeRequestCount: sourceBarcodeRequests,
        sourceBarcodeRecoveryRequestCount: sourceBarcodeRecoveryRequests,
        sourceBarcodeRecoveryExecuted: sourceBarcodeRecoveryRequests > 0,
        isolatedMaskBarcodeRequestCount: isolatedMaskBarcodeRequests,
        isolatedMaskDetectionExecuted: isolatedMaskBarcodeRequests > 0,
        maskingStrategy: maskingStrategy,
        projectiveMaskingApplied: projectiveMaskingApplied,
        projectiveMaskFallbackCount: projectiveMaskFallbacks
      )
    }
  }
#endif
