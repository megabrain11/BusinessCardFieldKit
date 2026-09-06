import AppleVisionBenchmarking
import Foundation

#if canImport(Darwin)
  import Darwin
#endif

struct PrivateBackArguments {
  var warmupRuns: Int
  var measuredRuns: Int
  var prettyPrinted: Bool

  static func parse(_ arguments: [String]) throws -> Self {
    var warmupRuns = 1
    var measuredRuns = 3
    var prettyPrinted = false
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
      case "--help", "-h":
        throw PrivateBackArgumentError.helpRequested
      default:
        throw PrivateBackArgumentError.unexpectedArgument
      }
      index += 1
    }
    return Self(
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      prettyPrinted: prettyPrinted
    )
  }
}

enum PrivateBackArgumentError: Error {
  case helpRequested
  case invalidValue
  case unexpectedArgument
}

let usage = """
  Usage: card-field-private-back-benchmark [--warmup N] [--runs N] [--pretty]

  Reads manifest.json and its images only from PRIVATE_CARD_BACK_CORPUS_ROOT.
  Missing configuration emits a redacted skipped report and exits successfully.
  Completed reports contain aggregate metrics only, never payload, OCR, image, path, or case identity.
  """

func write(_ report: PrivateCardBackCommandReport, pretty: Bool) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
  FileHandle.standardOutput.write(try encoder.encode(report))
  FileHandle.standardOutput.write(Data("\n".utf8))
}

do {
  let arguments = try PrivateBackArguments.parse(Array(CommandLine.arguments.dropFirst()))
  guard let rootValue = ProcessInfo.processInfo.environment["PRIVATE_CARD_BACK_CORPUS_ROOT"],
    !rootValue.isEmpty
  else {
    try write(.skipped, pretty: arguments.prettyPrinted)
    exit(0)
  }
  let root = URL(fileURLWithPath: rootValue, isDirectory: true)
  let manifest = try PrivateCardBackManifest(
    data: Data(contentsOf: root.appendingPathComponent("manifest.json"))
  )
  let report = try PrivateCardBackBenchmarkRunner(
    warmupRuns: arguments.warmupRuns,
    measuredRuns: arguments.measuredRuns
  ).run(manifest: manifest, root: root)
  try write(.completed(report), pretty: arguments.prettyPrinted)
} catch PrivateBackArgumentError.helpRequested {
  print(usage)
} catch {
  FileHandle.standardError.write(Data("Private card-back benchmark failed.\n\(usage)\n".utf8))
  exit(1)
}
