import CardFieldEvaluation
import Foundation

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("Usage: card-field-eval <fixtures.json>\n".utf8))
  exit(64)
}

do {
  let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
  let fixtures = try FixtureRunner.decode(data: data)
  let report = try FixtureRunner.evaluate(fixtures)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  FileHandle.standardOutput.write(try encoder.encode(report))
  FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
  FileHandle.standardError.write(Data("Evaluation failed: \(error)\n".utf8))
  exit(1)
}
