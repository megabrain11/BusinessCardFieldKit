import AppleVisionBenchmarking
import Foundation

#if canImport(Darwin)
  import Darwin
#endif

struct BenchmarkArguments {
  var manifestPath: String
  var warmupRuns: Int
  var measuredRuns: Int
  var prettyPrinted: Bool
  var targetedEvidence: Bool
  var cardBackEvidence: Bool
  var cardBackMaskExperiment: Bool
  var barcodeDetectionRecoveryExperiment: Bool

  static func parse(_ arguments: [String]) throws -> Self {
    var manifestPath: String?
    var warmupRuns = 1
    var measuredRuns = 3
    var prettyPrinted = false
    var targetedEvidence = false
    var cardBackEvidence = false
    var cardBackMaskExperiment = false
    var barcodeDetectionRecoveryExperiment = false
    var index = 0

    while index < arguments.count {
      switch arguments[index] {
      case "--warmup":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]) else {
          throw ArgumentError.invalidValue("--warmup")
        }
        warmupRuns = value
      case "--runs":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]) else {
          throw ArgumentError.invalidValue("--runs")
        }
        measuredRuns = value
      case "--pretty":
        prettyPrinted = true
      case "--targeted-evidence":
        targetedEvidence = true
      case "--card-back-evidence":
        cardBackEvidence = true
      case "--card-back-mask-experiment":
        cardBackMaskExperiment = true
      case "--barcode-detection-recovery-experiment":
        barcodeDetectionRecoveryExperiment = true
      case "--help", "-h":
        throw ArgumentError.helpRequested
      default:
        guard !arguments[index].hasPrefix("-"), manifestPath == nil else {
          throw ArgumentError.unexpectedArgument(arguments[index])
        }
        manifestPath = arguments[index]
      }
      index += 1
    }

    guard let manifestPath else { throw ArgumentError.manifestRequired }
    return Self(
      manifestPath: manifestPath,
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      prettyPrinted: prettyPrinted,
      targetedEvidence: targetedEvidence,
      cardBackEvidence: cardBackEvidence,
      cardBackMaskExperiment: cardBackMaskExperiment,
      barcodeDetectionRecoveryExperiment: barcodeDetectionRecoveryExperiment
    )
  }
}

enum ArgumentError: Error {
  case helpRequested
  case manifestRequired
  case invalidValue(String)
  case unexpectedArgument(String)
}

let usage = """
  Usage: card-field-benchmark [--warmup N] [--runs N] [--pretty] [--targeted-evidence | --card-back-evidence | --card-back-mask-experiment | --barcode-detection-recovery-experiment] MANIFEST

  Runs aggregate-only OCR diagnostics over a synthetic manifest.
  --targeted-evidence compares targeted re-recognition enabled versus disabled.
  --card-back-evidence evaluates QR/vCard detection, merging, and latency.
  --card-back-mask-experiment pairs rectified redetection with exact projective source mapping.
  --barcode-detection-recovery-experiment pairs source detection with a default-off empty-result retry.
  The JSON report contains no OCR text, token values, images, or source paths.
  """

do {
  let arguments = try BenchmarkArguments.parse(Array(CommandLine.arguments.dropFirst()))
  let data = try Data(contentsOf: URL(fileURLWithPath: arguments.manifestPath))
  let encoder = JSONEncoder()
  encoder.outputFormatting =
    arguments.prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
  if [
    arguments.targetedEvidence, arguments.cardBackEvidence, arguments.cardBackMaskExperiment,
    arguments.barcodeDetectionRecoveryExperiment,
  ]
  .filter({ $0 }).count > 1 {
    throw ArgumentError.unexpectedArgument("Conflicting evidence modes")
  } else if arguments.cardBackEvidence {
    let report = try CardBackBenchmarkRunner(
      warmupRuns: arguments.warmupRuns,
      measuredRuns: arguments.measuredRuns
    ).run(manifest: CardBackCorpusManifest(data: data))
    FileHandle.standardOutput.write(try encoder.encode(report))
  } else if arguments.cardBackMaskExperiment {
    let report = try CardBackMaskingStrategyBenchmarkRunner(
      warmupRuns: arguments.warmupRuns,
      measuredRuns: arguments.measuredRuns
    ).run(manifest: CardBackCorpusManifest(data: data))
    FileHandle.standardOutput.write(try encoder.encode(report))
  } else if arguments.barcodeDetectionRecoveryExperiment {
    let report = try BarcodeDetectionRecoveryBenchmarkRunner(
      warmupRuns: arguments.warmupRuns,
      measuredRuns: arguments.measuredRuns
    ).run(manifest: CardBackCorpusManifest(data: data))
    FileHandle.standardOutput.write(try encoder.encode(report))
  } else if arguments.targetedEvidence {
    let manifest = try GoldenCorpusManifest(data: data)
    let report = try TargetedReRecognitionBenchmarkRunner(
      warmupRuns: arguments.warmupRuns,
      measuredRuns: arguments.measuredRuns
    ).run(manifest: manifest)
    FileHandle.standardOutput.write(try encoder.encode(report))
  } else {
    let manifest = try GoldenCorpusManifest(data: data)
    let report = try DiagnosticsBenchmarkRunner(
      warmupRuns: arguments.warmupRuns,
      measuredRuns: arguments.measuredRuns
    ).run(manifest: manifest)
    FileHandle.standardOutput.write(try encoder.encode(report))
  }
  FileHandle.standardOutput.write(Data("\n".utf8))
} catch ArgumentError.helpRequested {
  print(usage)
} catch {
  FileHandle.standardError.write(Data("Benchmark failed.\n\(usage)\n".utf8))
  exit(1)
}
