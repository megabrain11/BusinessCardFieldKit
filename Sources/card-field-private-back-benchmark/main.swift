import AppleVisionBenchmarking
import Foundation

#if canImport(Darwin)
  import Darwin
#endif

struct PrivateBackArguments {
  var warmupRuns: Int
  var measuredRuns: Int
  var prettyPrinted: Bool
  var projectiveMaskExperiment: Bool
  var barcodeDetectionRecoveryExperiment: Bool

  static func parse(_ arguments: [String]) throws -> Self {
    var warmupRuns = 1
    var measuredRuns = 3
    var prettyPrinted = false
    var projectiveMaskExperiment = false
    var barcodeDetectionRecoveryExperiment = false
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--warmup":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]) else {
          throw PrivateBackArgumentError.invalidValue
        }
        warmupRuns = value
      case "--runs":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]) else {
          throw PrivateBackArgumentError.invalidValue
        }
        measuredRuns = value
      case "--pretty":
        prettyPrinted = true
      case "--projective-mask-experiment":
        projectiveMaskExperiment = true
      case "--barcode-detection-recovery-experiment":
        barcodeDetectionRecoveryExperiment = true
      case "--help", "-h":
        throw PrivateBackArgumentError.helpRequested
      default:
        throw PrivateBackArgumentError.unexpectedArgument
      }
      index += 1
    }
    guard !(projectiveMaskExperiment && barcodeDetectionRecoveryExperiment) else {
      throw PrivateBackArgumentError.conflictingExperiments
    }
    return Self(
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      prettyPrinted: prettyPrinted,
      projectiveMaskExperiment: projectiveMaskExperiment,
      barcodeDetectionRecoveryExperiment: barcodeDetectionRecoveryExperiment
    )
  }
}

enum PrivateBackArgumentError: Error {
  case helpRequested
  case invalidValue
  case unexpectedArgument
  case conflictingExperiments
  case conflictingRoots
}

let usage = """
  Usage: card-field-private-back-benchmark [--warmup N] [--runs N] [--pretty] [--projective-mask-experiment | --barcode-detection-recovery-experiment]

  Reads manifest.json and its images only from PRIVATE_CARD_BACK_CORPUS_ROOT
  (or the legacy-compatible PRIVATE_CARD_CORPUS_ROOT alias).
  Missing configuration emits a redacted skipped report and exits successfully.
  Completed reports contain aggregate metrics only, never payload, OCR, image, path, or case identity.
  --projective-mask-experiment alternates default/projective scans and reports aggregate parity and cost deltas.
  --barcode-detection-recovery-experiment alternates default/recovery scans, requires at least three runs,
  and applies a fixed 250 ms p95 delta review budget without changing scanner defaults.
  """

func write(_ report: PrivateCardBackCommandReport, pretty: Bool) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
  FileHandle.standardOutput.write(try encoder.encode(report))
  FileHandle.standardOutput.write(Data("\n".utf8))
}

do {
  let arguments = try PrivateBackArguments.parse(Array(CommandLine.arguments.dropFirst()))
  let environment = ProcessInfo.processInfo.environment
  let primaryRoot = environment["PRIVATE_CARD_BACK_CORPUS_ROOT"].flatMap { $0.isEmpty ? nil : $0 }
  let aliasRoot = environment["PRIVATE_CARD_CORPUS_ROOT"].flatMap { $0.isEmpty ? nil : $0 }
  guard primaryRoot == nil || aliasRoot == nil || primaryRoot == aliasRoot else {
    throw PrivateBackArgumentError.conflictingRoots
  }
  guard let rootValue = primaryRoot ?? aliasRoot else {
    try write(.skipped, pretty: arguments.prettyPrinted)
    exit(0)
  }
  let root = URL(fileURLWithPath: rootValue, isDirectory: true)
  let manifest = try PrivateCardBackManifest(root: root)
  let runner = PrivateCardBackBenchmarkRunner(
    warmupRuns: arguments.warmupRuns,
    measuredRuns: arguments.measuredRuns
  )
  if arguments.projectiveMaskExperiment {
    let comparison = try runner.runMaskingExperiment(manifest: manifest, root: root)
    try write(.completedMaskingComparison(comparison), pretty: arguments.prettyPrinted)
  } else if arguments.barcodeDetectionRecoveryExperiment {
    let comparison = try runner.runBarcodeDetectionRecoveryExperiment(
      manifest: manifest,
      root: root
    )
    try write(.completedBarcodeRecoveryComparison(comparison), pretty: arguments.prettyPrinted)
  } else {
    let report = try runner.run(manifest: manifest, root: root)
    try write(.completed(report), pretty: arguments.prettyPrinted)
  }
} catch PrivateBackArgumentError.helpRequested {
  print(usage)
} catch {
  FileHandle.standardError.write(Data("Private card-back benchmark failed.\n\(usage)\n".utf8))
  exit(1)
}
