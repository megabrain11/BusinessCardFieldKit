import AppleVisionBenchmarking
import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  let goldenSceneRepository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  enum GoldenSceneManifest {
    static func manifest(relativePath: String) throws -> GoldenCorpusManifest {
      try GoldenCorpusManifest(
        data: Data(
          contentsOf: goldenSceneRepository.appendingPathComponent(relativePath)
        )
      )
    }

    static func manifest() throws -> GoldenCorpusManifest {
      try manifest(relativePath: "Fixtures/GoldenScenes/manifest.json")
    }

    static func load() throws -> [GoldenSceneCase] {
      try manifest().expandedCases()
    }
  }

  enum TargetedStressManifest {
    static func manifest() throws -> GoldenCorpusManifest {
      try GoldenSceneManifest.manifest(
        relativePath: "Fixtures/TargetedReRecognition/manifest.json")
    }

    static func load() throws -> [GoldenSceneCase] {
      try manifest().expandedCases()
    }
  }

  enum GoldenFieldComparator {
    static func mismatches(
      expected: [String: [String]], result: CardFieldResult
    ) -> [String] {
      GoldenFieldComparison.mismatchedFields(expected: expected, result: result)
    }

    static func digits(_ value: String) -> String {
      value.filter(\.isNumber)
    }
  }
#endif
