import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  /// Opt-in collection options for privacy-safe Apple Vision scan diagnostics.
  ///
  /// Diagnostics are disabled by default. Enabling them adds timing and request
  /// counters to completed results without retaining OCR text, image bytes,
  /// geometry, paths, or token values.
  public struct AppleVisionDiagnosticsOptions: Equatable, Sendable {
    /// Whether a completed scan includes an `AppleVisionScanDiagnostics` payload.
    public var isEnabled: Bool

    /// Monotonic clock used for elapsed-time measurement. Hosts normally use
    /// the default system clock; the injectable surface makes reports
    /// deterministic in tests.
    public var clock: any AppleVisionDiagnosticsClock

    public init(
      isEnabled: Bool = false,
      clock: any AppleVisionDiagnosticsClock = AppleVisionDiagnosticsSystemClock()
    ) {
      self.isEnabled = isEnabled
      self.clock = clock
    }

    /// The default no-measurement diagnostics policy.
    public static let disabled = AppleVisionDiagnosticsOptions()

    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.isEnabled == rhs.isEnabled
    }
  }

  /// Clock abstraction used only to measure elapsed scan stages.
  public protocol AppleVisionDiagnosticsClock: Sendable {
    func nowMilliseconds() -> Double
  }

  /// Production monotonic diagnostics clock.
  public struct AppleVisionDiagnosticsSystemClock: AppleVisionDiagnosticsClock {
    public init() {}

    public func nowMilliseconds() -> Double {
      ProcessInfo.processInfo.systemUptime * 1_000
    }
  }

  /// Stable stage identifiers emitted in deterministic pipeline order.
  public enum AppleVisionScanStage: String, Codable, CaseIterable, Sendable {
    case imageDecoding
    case preprocessing
    case cardDetection
    case saliencyFallback
    case primaryRecognition
    case secondaryRecognition
    case dualPassMerge
    case targetedReRecognition
    case classification
    case total
  }

  /// One aggregate stage duration. Repeated candidate or refinement requests are
  /// accumulated under the same stable stage identifier.
  public struct AppleVisionStageTiming: Codable, Equatable, Sendable {
    public var stage: AppleVisionScanStage
    public var durationMilliseconds: Double

    public init(stage: AppleVisionScanStage, durationMilliseconds: Double) {
      self.stage = stage
      self.durationMilliseconds = max(durationMilliseconds, 0)
    }
  }

  /// Privacy-safe diagnostics for one completed scan.
  ///
  /// The contract deliberately contains only fixed identifiers, durations,
  /// counts, and booleans. It must never contain OCR text, token values,
  /// confidence readings, geometry, image data, or filesystem paths.
  public struct AppleVisionScanDiagnostics: Codable, Equatable, Sendable {
    /// Diagnostics schema understood by this package.
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var stageTimings: [AppleVisionStageTiming]

    public var totalVisionRequestCount: Int
    public var rectangleRequestCount: Int
    public var saliencyRequestCount: Int
    public var textRecognitionRequestCount: Int
    public var primaryTextRecognitionRequestCount: Int
    public var secondaryTextRecognitionRequestCount: Int
    public var targetedReRecognitionRequestCount: Int

    public var dualPassConfigured: Bool
    public var dualPassExecuted: Bool
    public var conditionalDualPassConfigured: Bool
    public var dualPassSkipCount: Int
    public var dualPassDecisionCounts: [AppleVisionDualPassDecisionCount]
    public var targetedReRecognitionConfigured: Bool
    public var targetedReRecognitionExecuted: Bool
    public var cardIsolationConfigured: Bool
    public var cardIsolationAttempted: Bool
    public var cardIsolationSucceeded: Bool
    public var fullImageFallbackUsed: Bool

    public init(
      schemaVersion: Int = AppleVisionScanDiagnostics.currentSchemaVersion,
      stageTimings: [AppleVisionStageTiming],
      totalVisionRequestCount: Int,
      rectangleRequestCount: Int,
      saliencyRequestCount: Int,
      textRecognitionRequestCount: Int,
      primaryTextRecognitionRequestCount: Int,
      secondaryTextRecognitionRequestCount: Int,
      targetedReRecognitionRequestCount: Int,
      dualPassConfigured: Bool,
      dualPassExecuted: Bool,
      conditionalDualPassConfigured: Bool = false,
      dualPassSkipCount: Int = 0,
      dualPassDecisionCounts: [AppleVisionDualPassDecisionCount] = [],
      targetedReRecognitionConfigured: Bool,
      targetedReRecognitionExecuted: Bool,
      cardIsolationConfigured: Bool,
      cardIsolationAttempted: Bool,
      cardIsolationSucceeded: Bool,
      fullImageFallbackUsed: Bool
    ) {
      self.schemaVersion = schemaVersion
      self.stageTimings = stageTimings
      self.totalVisionRequestCount = max(totalVisionRequestCount, 0)
      self.rectangleRequestCount = max(rectangleRequestCount, 0)
      self.saliencyRequestCount = max(saliencyRequestCount, 0)
      self.textRecognitionRequestCount = max(textRecognitionRequestCount, 0)
      self.primaryTextRecognitionRequestCount = max(primaryTextRecognitionRequestCount, 0)
      self.secondaryTextRecognitionRequestCount = max(secondaryTextRecognitionRequestCount, 0)
      self.targetedReRecognitionRequestCount = max(targetedReRecognitionRequestCount, 0)
      self.dualPassConfigured = dualPassConfigured
      self.dualPassExecuted = dualPassExecuted
      self.conditionalDualPassConfigured = conditionalDualPassConfigured
      self.dualPassSkipCount = max(dualPassSkipCount, 0)
      self.dualPassDecisionCounts = dualPassDecisionCounts
      self.targetedReRecognitionConfigured = targetedReRecognitionConfigured
      self.targetedReRecognitionExecuted = targetedReRecognitionExecuted
      self.cardIsolationConfigured = cardIsolationConfigured
      self.cardIsolationAttempted = cardIsolationAttempted
      self.cardIsolationSucceeded = cardIsolationSucceeded
      self.fullImageFallbackUsed = fullImageFallbackUsed
    }

    private enum CodingKeys: String, CodingKey {
      case schemaVersion, stageTimings, totalVisionRequestCount, rectangleRequestCount
      case saliencyRequestCount, textRecognitionRequestCount
      case primaryTextRecognitionRequestCount, secondaryTextRecognitionRequestCount
      case targetedReRecognitionRequestCount, dualPassConfigured, dualPassExecuted
      case conditionalDualPassConfigured, dualPassSkipCount, dualPassDecisionCounts
      case targetedReRecognitionConfigured, targetedReRecognitionExecuted
      case cardIsolationConfigured, cardIsolationAttempted, cardIsolationSucceeded
      case fullImageFallbackUsed
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
        schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
        stageTimings: try container.decode([AppleVisionStageTiming].self, forKey: .stageTimings),
        totalVisionRequestCount: try container.decode(Int.self, forKey: .totalVisionRequestCount),
        rectangleRequestCount: try container.decode(Int.self, forKey: .rectangleRequestCount),
        saliencyRequestCount: try container.decode(Int.self, forKey: .saliencyRequestCount),
        textRecognitionRequestCount: try container.decode(
          Int.self, forKey: .textRecognitionRequestCount),
        primaryTextRecognitionRequestCount: try container.decode(
          Int.self, forKey: .primaryTextRecognitionRequestCount),
        secondaryTextRecognitionRequestCount: try container.decode(
          Int.self, forKey: .secondaryTextRecognitionRequestCount),
        targetedReRecognitionRequestCount: try container.decode(
          Int.self, forKey: .targetedReRecognitionRequestCount),
        dualPassConfigured: try container.decode(Bool.self, forKey: .dualPassConfigured),
        dualPassExecuted: try container.decode(Bool.self, forKey: .dualPassExecuted),
        conditionalDualPassConfigured: try container.decodeIfPresent(
          Bool.self, forKey: .conditionalDualPassConfigured) ?? false,
        dualPassSkipCount: try container.decodeIfPresent(
          Int.self, forKey: .dualPassSkipCount) ?? 0,
        dualPassDecisionCounts: try container.decodeIfPresent(
          [AppleVisionDualPassDecisionCount].self, forKey: .dualPassDecisionCounts) ?? [],
        targetedReRecognitionConfigured: try container.decode(
          Bool.self, forKey: .targetedReRecognitionConfigured),
        targetedReRecognitionExecuted: try container.decode(
          Bool.self, forKey: .targetedReRecognitionExecuted),
        cardIsolationConfigured: try container.decode(Bool.self, forKey: .cardIsolationConfigured),
        cardIsolationAttempted: try container.decode(Bool.self, forKey: .cardIsolationAttempted),
        cardIsolationSucceeded: try container.decode(Bool.self, forKey: .cardIsolationSucceeded),
        fullImageFallbackUsed: try container.decode(Bool.self, forKey: .fullImageFallbackUsed)
      )
    }
  }

  public struct AppleVisionDualPassDecisionCount: Codable, Equatable, Sendable {
    public var reason: AppleVisionDualPassDecisionReason
    public var count: Int

    public init(reason: AppleVisionDualPassDecisionReason, count: Int) {
      self.reason = reason
      self.count = max(count, 0)
    }
  }

  /// Mutable per-scan state. The scanner creates it only when diagnostics are
  /// enabled, so the default path performs no clock reads or locking.
  final class ScanInstrumentation: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: any AppleVisionDiagnosticsClock
    private let startedAt: Double
    private var durations: [AppleVisionScanStage: Double] = [:]
    private var rectangleRequests = 0
    private var saliencyRequests = 0
    private var primaryTextRequests = 0
    private var secondaryTextRequests = 0
    private var targetedTextRequests = 0
    private var dualPassWasExecuted = false
    private var dualPassDecisions: [AppleVisionDualPassDecisionReason: Int] = [:]
    private var cardIsolationWasAttempted = false
    private var cardIsolationDidSucceed = false
    private var usedFullImageFallback = false

    init(clock: any AppleVisionDiagnosticsClock) {
      self.clock = clock
      self.startedAt = clock.nowMilliseconds()
    }

    func measure<T>(_ stage: AppleVisionScanStage, _ operation: () throws -> T) rethrows -> T {
      let stageStart = clock.nowMilliseconds()
      defer {
        let elapsed = max(clock.nowMilliseconds() - stageStart, 0)
        lock.lock()
        durations[stage, default: 0] += elapsed
        lock.unlock()
      }
      return try operation()
    }

    func recordRectangleRequest() {
      lock.lock()
      rectangleRequests += 1
      lock.unlock()
    }

    func recordSaliencyRequest() {
      lock.lock()
      saliencyRequests += 1
      lock.unlock()
    }

    func recordTextRequest(secondary: Bool, targeted: Bool) {
      lock.lock()
      if secondary {
        secondaryTextRequests += 1
      } else {
        primaryTextRequests += 1
      }
      if targeted { targetedTextRequests += 1 }
      lock.unlock()
    }

    func recordDualPassExecuted() {
      lock.lock()
      dualPassWasExecuted = true
      lock.unlock()
    }

    func recordDualPassDecision(_ reason: AppleVisionDualPassDecisionReason) {
      lock.lock()
      dualPassDecisions[reason, default: 0] += 1
      lock.unlock()
    }

    func recordCardIsolationAttempted() {
      lock.lock()
      cardIsolationWasAttempted = true
      lock.unlock()
    }

    func recordCardIsolationSucceeded() {
      lock.lock()
      cardIsolationDidSucceed = true
      lock.unlock()
    }

    func recordFullImageFallback() {
      lock.lock()
      usedFullImageFallback = true
      lock.unlock()
    }

    func snapshot(configuration: AppleVisionScanConfiguration) -> AppleVisionScanDiagnostics {
      lock.lock()
      defer { lock.unlock() }

      var orderedTimings = AppleVisionScanStage.allCases.compactMap { stage in
        durations[stage].map { AppleVisionStageTiming(stage: stage, durationMilliseconds: $0) }
      }
      orderedTimings.append(
        AppleVisionStageTiming(
          stage: .total,
          durationMilliseconds: max(clock.nowMilliseconds() - startedAt, 0)
        )
      )

      let textRequests = primaryTextRequests + secondaryTextRequests
      let decisionCounts = AppleVisionDualPassDecisionReason.allCases.compactMap { reason in
        dualPassDecisions[reason].map {
          AppleVisionDualPassDecisionCount(reason: reason, count: $0)
        }
      }
      return AppleVisionScanDiagnostics(
        stageTimings: orderedTimings,
        totalVisionRequestCount: rectangleRequests + saliencyRequests + textRequests,
        rectangleRequestCount: rectangleRequests,
        saliencyRequestCount: saliencyRequests,
        textRecognitionRequestCount: textRequests,
        primaryTextRecognitionRequestCount: primaryTextRequests,
        secondaryTextRecognitionRequestCount: secondaryTextRequests,
        targetedReRecognitionRequestCount: targetedTextRequests,
        dualPassConfigured: configuration.dualPassRecognition
          && configuration.recognitionLevel == .accurate,
        dualPassExecuted: dualPassWasExecuted,
        conditionalDualPassConfigured: configuration.conditionalDualPass.mode == .enabled,
        dualPassSkipCount: dualPassDecisions[.eligible] ?? 0,
        dualPassDecisionCounts: decisionCounts,
        targetedReRecognitionConfigured: configuration.performsTargetedReRecognition
          && configuration.targetedReRecognitionConfidenceLimit > 0,
        targetedReRecognitionExecuted: targetedTextRequests > 0,
        cardIsolationConfigured: configuration.cardRegion.mode == .automatic,
        cardIsolationAttempted: cardIsolationWasAttempted,
        cardIsolationSucceeded: cardIsolationDidSucceed,
        fullImageFallbackUsed: usedFullImageFallback
      )
    }
  }
#endif
