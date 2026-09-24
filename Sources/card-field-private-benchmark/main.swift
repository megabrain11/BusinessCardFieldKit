import AppleVisionBenchmarking
import Foundation

#if canImport(Darwin)
  import Darwin
#endif

struct PrivateBenchmarkArguments {
  var warmupRuns: Int
  var measuredRuns: Int
  var bootstrapIterations: Int
  var prettyPrinted: Bool

  static func parse(_ arguments: [String]) throws -> Self {
    var warmupRuns = 1
    var measuredRuns = 3
    var bootstrapIterations = 2_000
    var prettyPrinted = false
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--warmup":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]) else {
          throw PrivateArgumentError.invalidValue
        }
        warmupRuns = value
      case "--runs":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]) else {
          throw PrivateArgumentError.invalidValue
        }
        measuredRuns = value
      case "--bootstrap":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]) else {
          throw PrivateArgumentError.invalidValue
        }
        bootstrapIterations = value
      case "--pretty":
        prettyPrinted = true
      case "--help", "-h":
        throw PrivateArgumentError.helpRequested
      default:
        throw PrivateArgumentError.unexpectedArgument
      }
      index += 1
    }
    return Self(
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      bootstrapIterations: bootstrapIterations,
      prettyPrinted: prettyPrinted
    )
  }
}

enum PrivateArgumentError: Error {
  case helpRequested
  case invalidValue
  case unexpectedArgument
}

let usage = """
  Usage: card-field-private-benchmark [--warmup N] [--runs N] [--bootstrap N] [--pretty]

  Reads manifest.json and its images only from PRIVATE_CARD_CORPUS_ROOT.
  Missing configuration emits a redacted skipped report and exits successfully.
  Completed reports contain aggregate metrics only, never OCR, image, path, or case identity.
  """

func write(_ report: PrivateHoldoutCommandReport, pretty: Bool) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
  FileHandle.standardOutput.write(try encoder.encode(report))
  FileHandle.standardOutput.write(Data("\n".utf8))
}

do {
  let arguments = try PrivateBenchmarkArguments.parse(Array(CommandLine.arguments.dropFirst()))
  guard let rootValue = ProcessInfo.processInfo.environment["PRIVATE_CARD_CORPUS_ROOT"],
    !rootValue.isEmpty
  else {
    try write(.skipped, pretty: arguments.prettyPrinted)
    exit(0)
  }
  let root = URL(fileURLWithPath: rootValue, isDirectory: true)
  let manifestData = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
  let manifest = try PrivateHoldoutManifest(data: manifestData)
  let report = try PrivateHoldoutBenchmarkRunner(
    warmupRuns: arguments.warmupRuns,
    measuredRuns: arguments.measuredRuns,
    bootstrapIterations: arguments.bootstrapIterations
  ).run(manifest: manifest, root: root)
  try write(.completed(report), pretty: arguments.prettyPrinted)
} catch PrivateArgumentError.helpRequested {
  print(usage)
} catch {
  FileHandle.standardError.write(Data("Private holdout failed.\n\(usage)\n".utf8))
  exit(1)
}
