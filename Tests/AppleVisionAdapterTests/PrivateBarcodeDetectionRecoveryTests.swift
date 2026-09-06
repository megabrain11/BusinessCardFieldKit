import Foundation
import Testing

@testable import AppleVisionBenchmarking

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import ImageIO
  import UniformTypeIdentifiers

  @Test("Private barcode recovery emits only aggregate truth-aware evidence")
  func privateBarcodeRecoveryEvidence() throws {
    let stress = try stressManifest()
    let success = try #require(stress.cases.first { $0.identifier == "qr-stress-01-small" })
    let detectionOnly = try #require(
      stress.cases.first { $0.identifier == "qr-stress-13-dot-style" }
    )
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writePNG(
      CardBackSceneRenderer.render(success),
      to: root.appendingPathComponent("private-success.png")
    )
    try writePNG(
      CardBackSceneRenderer.render(detectionOnly),
      to: root.appendingPathComponent("private-detection-only.png")
    )
    let manifestData = try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "cases": [
        privateCase(
          image: "private-success.png",
          expectedPayloadKinds: success.expectedPayloadKinds.map(\.rawValue),
          backExpected: success.backExpected,
          mergedExpected: success.mergedExpected
        ),
        privateCase(
          image: "private-detection-only.png",
          expectedPayloadKinds: [],
          backExpected: [:],
          mergedExpected: [:],
          barcodeTruthAvailable: false,
          fieldTruthAvailable: false
        ),
      ],
    ])
    try manifestData.write(to: root.appendingPathComponent("manifest.json"))
    let manifest = try PrivateCardBackManifest(root: root)
    let comparison = try PrivateCardBackBenchmarkRunner(warmupRuns: 0, measuredRuns: 3)
      .runBarcodeDetectionRecoveryExperiment(manifest: manifest, root: root)

    #expect(comparison.caseCount == 2)
    #expect(comparison.barcodeTruthCaseCount == 1)
    #expect(comparison.detectionOnlyCaseCount == 1)
    #expect(comparison.fieldTruthCaseCount == 1)
    #expect(comparison.measuredPairCount == 6)
    #expect(comparison.baselineDetectionRate == 0.5)
    #expect(comparison.experimentalDetectionRate == 1)
    #expect(comparison.detectionOnlyBaselineDetectionRate == 0)
    #expect(comparison.detectionOnlyExperimentalDetectionRate == 1)
    #expect(comparison.recoveredSampleCount == 3)
    #expect(comparison.recoveredDistinctCaseCount == 1)
    #expect(comparison.regressedSampleCount == 0)
    #expect(comparison.baselineDetectionPreservationRate == 1)
    #expect(comparison.fieldRegressionSampleCount == 0)
    #expect(comparison.baselineFieldPreservationRate == 1)
    #expect(comparison.recoveryExecutedSampleCount == 3)
    #expect(comparison.baselineSourceBarcodeRequests.p95 == 1)
    #expect(comparison.experimentalSourceBarcodeRequests.p95 == 2)
    #expect(comparison.gate.assessment == .insufficientEvidence)
    #expect(!comparison.gate.enoughBaselineFailureDiversity)

    let envelope = PrivateCardBackCommandReport.completedBarcodeRecoveryComparison(comparison)
    let json = try #require(
      String(data: JSONEncoder().encode(envelope), encoding: .utf8)
    ).lowercased()
    for forbidden in [
      "private-success.png", "private-detection-only.png", "qr01.example.net",
      "qr13.example.net", "qr.stress@example.net", root.path.lowercased(),
      "expectedpayloadkinds", "backexpected", "detectedbarcodes", "tokens", "ocr",
    ] {
      #expect(!json.contains(forbidden))
    }
  }

  @Test("Private barcode recovery requires three measured runs")
  func privateBarcodeRecoveryRunCount() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0]).write(to: root.appendingPathComponent("sample.png"))
    let manifest = try PrivateCardBackManifest(
      data: try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1,
        "cases": [privateCase(image: "sample.png")],
      ])
    )
    #expect(throws: CardBackBenchmarkError.invalidRunCount) {
      try PrivateCardBackBenchmarkRunner(warmupRuns: 0, measuredRuns: 2)
        .runBarcodeDetectionRecoveryExperiment(manifest: manifest, root: root)
    }
  }

  @Test("Private recovery gate distinguishes insufficient failed and reviewable evidence")
  func privateBarcodeRecoveryGate() {
    let insufficient = PrivateBarcodeRecoveryGate.assess(
      recoveredDistinctCases: 3,
      baselineFailureDistinctCases: 3,
      baselineSuccessDistinctCases: 2,
      detectionRegressionCount: 0,
      baselineDetectionPreserved: true,
      fieldRegressionCount: 0,
      p95DurationDeltaMilliseconds: 10,
      maximumP95DurationDeltaMilliseconds: 250
    )
    #expect(insufficient.assessment == .insufficientEvidence)

    let failed = PrivateBarcodeRecoveryGate.assess(
      recoveredDistinctCases: 4,
      baselineFailureDistinctCases: 4,
      baselineSuccessDistinctCases: 2,
      detectionRegressionCount: 1,
      baselineDetectionPreserved: false,
      fieldRegressionCount: 1,
      p95DurationDeltaMilliseconds: 251,
      maximumP95DurationDeltaMilliseconds: 250
    )
    #expect(failed.assessment == .criteriaNotMet)
    #expect(!failed.noDetectionRegression)
    #expect(!failed.noFieldRegression)
    #expect(!failed.latencyWithinBudget)

    let eligible = PrivateBarcodeRecoveryGate.assess(
      recoveredDistinctCases: 4,
      baselineFailureDistinctCases: 4,
      baselineSuccessDistinctCases: 2,
      detectionRegressionCount: 0,
      baselineDetectionPreserved: true,
      fieldRegressionCount: 0,
      p95DurationDeltaMilliseconds: 250,
      maximumP95DurationDeltaMilliseconds: 250
    )
    #expect(eligible.assessment == .eligibleForHumanReview)
    #expect(eligible.minimumRecoveredDistinctCases == 4)
    #expect(eligible.latencyWithinBudget)
  }

  @Test("Private card-back boundary rejects root manifest and image symlinks")
  func privateBarcodeRecoveryRejectsSymlinks() throws {
    let container = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: container) }
    let root = container.appendingPathComponent("corpus", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let manifestData = try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "cases": [privateCase(image: "sample.png")],
    ])
    try manifestData.write(to: root.appendingPathComponent("manifest.json"))
    try Data([0]).write(to: root.appendingPathComponent("sample.png"))

    let linkedRoot = container.appendingPathComponent("linked-root")
    try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
    #expect(throws: PrivateCardBackBoundaryError.symbolicLinkUnsupported) {
      try PrivateCardBackManifest(root: linkedRoot)
    }

    let linkedImage = root.appendingPathComponent("linked.png")
    try FileManager.default.createSymbolicLink(
      at: linkedImage,
      withDestinationURL: root.appendingPathComponent("sample.png")
    )
    let linkedImageManifest = try PrivateCardBackManifest(
      data: try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1,
        "cases": [privateCase(image: "linked.png")],
      ])
    )
    #expect(throws: PrivateCardBackBoundaryError.symbolicLinkUnsupported) {
      try linkedImageManifest.validatedCases(root: root)
    }

    let manifestTarget = container.appendingPathComponent("manifest-target.json")
    try manifestData.write(to: manifestTarget)
    try FileManager.default.removeItem(at: root.appendingPathComponent("manifest.json"))
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("manifest.json"),
      withDestinationURL: manifestTarget
    )
    #expect(throws: PrivateCardBackBoundaryError.symbolicLinkUnsupported) {
      try PrivateCardBackManifest(root: root)
    }
  }

  @Test("Detection-only declarations cannot carry hidden truth labels")
  func privateBarcodeRecoveryTruthBoundary() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0]).write(to: root.appendingPathComponent("sample.png"))
    let barcodeConflict = try PrivateCardBackManifest(
      data: try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1,
        "cases": [
          privateCase(
            image: "sample.png",
            expectedPayloadKinds: ["url"],
            barcodeTruthAvailable: false
          )
        ],
      ])
    )
    #expect(throws: PrivateCardBackBoundaryError.invalidTruthBoundary) {
      try barcodeConflict.validatedCases(root: root)
    }

    let fieldConflict = try PrivateCardBackManifest(
      data: try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1,
        "cases": [
          privateCase(
            image: "sample.png",
            backExpected: ["websites": ["https://private.example/card"]],
            fieldTruthAvailable: false
          )
        ],
      ])
    )
    #expect(throws: PrivateCardBackBoundaryError.invalidTruthBoundary) {
      try fieldConflict.validatedCases(root: root)
    }
  }

  private func privateCase(
    image: String,
    expectedPayloadKinds: [String] = [],
    backExpected: [String: [String]] = [:],
    mergedExpected: [String: [String]] = [:],
    barcodeTruthAvailable: Bool? = nil,
    fieldTruthAvailable: Bool? = nil
  ) -> [String: Any] {
    var value: [String: Any] = [
      "image": image,
      "expectedPayloadKinds": expectedPayloadKinds,
      "backExpected": backExpected,
      "mergedExpected": mergedExpected,
      "reviewExpected": false,
      "attemptsCardIsolation": false,
    ]
    if let barcodeTruthAvailable { value["barcodeTruthAvailable"] = barcodeTruthAvailable }
    if let fieldTruthAvailable { value["fieldTruthAvailable"] = fieldTruthAvailable }
    return value
  }

  private func stressManifest() throws -> CardBackCorpusManifest {
    try CardBackCorpusManifest(
      data: Data(
        contentsOf:
          repositoryRoot
          .appendingPathComponent("Fixtures/BarcodeDetectionStress/manifest.json")
      )
    )
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func temporaryDirectory() -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func writePNG(_ image: CGImage, to url: URL) throws {
    let destination = try #require(
      CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    )
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
  }
#else
  @Test("Private barcode recovery requires Apple Vision")
  func privateBarcodeRecoveryUnavailable() {}
#endif
