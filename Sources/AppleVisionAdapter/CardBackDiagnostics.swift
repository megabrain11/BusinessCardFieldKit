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
  /// execution boolean. It never contains payloads, OCR text, image data,
  /// geometry, token values, or paths.
  public struct AppleVisionBackScanDiagnostics: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var stageTimings: [AppleVisionBackStageTiming]
    public var totalBarcodeRequestCount: Int
    public var sourceBarcodeRequestCount: Int
    public var isolatedMaskBarcodeRequestCount: Int
    public var isolatedMaskDetectionExecuted: Bool

    public init(
      schemaVersion: Int = AppleVisionBackScanDiagnostics.currentSchemaVersion,
      stageTimings: [AppleVisionBackStageTiming],
      totalBarcodeRequestCount: Int,
      sourceBarcodeRequestCount: Int,
      isolatedMaskBarcodeRequestCount: Int,
      isolatedMaskDetectionExecuted: Bool
    ) {
      self.schemaVersion = schemaVersion
      self.stageTimings = stageTimings
      self.totalBarcodeRequestCount = max(totalBarcodeRequestCount, 0)
      self.sourceBarcodeRequestCount = max(sourceBarcodeRequestCount, 0)
      self.isolatedMaskBarcodeRequestCount = max(isolatedMaskBarcodeRequestCount, 0)
      self.isolatedMaskDetectionExecuted = isolatedMaskDetectionExecuted
    }
  }

  final class BackScanInstrumentation: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: any AppleVisionDiagnosticsClock
    private let startedAt: Double
    private var durations: [AppleVisionBackScanStage: Double] = [:]
    private var sourceBarcodeRequests = 0
    private var isolatedMaskBarcodeRequests = 0

    init(clock: any AppleVisionDiagnosticsClock) {
      self.clock = clock
      self.startedAt = clock.nowMilliseconds()
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

    func recordIsolatedMaskBarcodeRequest() {
      lock.lock()
      isolatedMaskBarcodeRequests += 1
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
        isolatedMaskBarcodeRequestCount: isolatedMaskBarcodeRequests,
        isolatedMaskDetectionExecuted: isolatedMaskBarcodeRequests > 0
      )
    }
  }
#endif
