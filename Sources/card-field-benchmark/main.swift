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

  static func parse(_ arguments: [String]) throws -> Self {
    var manifestPath: String?
    var warmupRuns = 1
    var measuredRuns = 3
    var prettyPrinted = false
    var targetedEvidence = false
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
      targetedEvidence: targetedEvidence
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
  Usage: card-field-benchmark [--warmup N] [--runs N] [--pretty] [--targeted-evidence] MANIFEST

  Runs aggregate-only OCR diagnostics over a synthetic manifest.
  --targeted-evidence compares targeted re-recognition enabled versus disabled.
  The JSON report contains no OCR text, token values, images, or source paths.
  """

do {
  let arguments = try BenchmarkArguments.parse(Array(CommandLine.arguments.dropFirst()))
  let data = try Data(contentsOf: URL(fileURLWithPath: arguments.manifestPath))
  let manifest = try GoldenCorpusManifest(data: data)
  let encoder = JSONEncoder()
  encoder.outputFormatting =
    arguments.prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
  if arguments.targetedEvidence {
    let report = try TargetedReRecognitionBenchmarkRunner(
      warmupRuns: arguments.warmupRuns,
      measuredRuns: arguments.measuredRuns
    ).run(manifest: manifest)
    FileHandle.standardOutput.write(try encoder.encode(report))
  } else {
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
