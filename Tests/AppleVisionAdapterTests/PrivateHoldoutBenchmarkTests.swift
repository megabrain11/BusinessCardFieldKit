import AppleVisionAdapter
import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionBenchmarking

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import ImageIO
  import UniformTypeIdentifiers

  @Test("Private holdout command reports are aggregate-only")
  func privateHoldoutReportIsRedacted() throws {
    let observations = privateObservations(caseCount: 4, targetedExecutions: 4)
    let report = PrivateHoldoutAggregator.makeReport(
      corpusSchemaVersion: 1,
      caseCount: 4,
      warmupRuns: 1,
      measuredRuns: 3,
      bootstrapIterations: 100,
      observations: observations
    )
    let data = try JSONEncoder().encode(PrivateHoldoutCommandReport.completed(report))
    let json = try #require(String(data: data, encoding: .utf8))
    for forbidden in [
      "private.person@", "caseIdentifier", "imagePath", "imageReference",
      "ocrText", "tokenValue", "tokenConfidence", "/" + "Users/", "manifest.json",
    ] {
      #expect(!json.localizedCaseInsensitiveContains(forbidden))
    }
    #expect(report.assessment == .eligibleForHumanReview)
    #expect(report.naturalExecutionCaseCount == 4)

    let skippedData = try JSONEncoder().encode(PrivateHoldoutCommandReport.skipped)
    let skipped = try #require(String(data: skippedData, encoding: .utf8))
    #expect(skipped.contains("privateCorpusUnavailable"))
    #expect(!skipped.contains("PRIVATE_CARD_CORPUS_ROOT"))
  }

  @Test("Private bootstrap is deterministic and independent of observation order")
  func privateBootstrapIsDeterministic() {
    let observations = privateObservations(caseCount: 5, targetedExecutions: 5)
    let forward = PrivateHoldoutAggregator.makeReport(
      corpusSchemaVersion: 1,
      caseCount: 5,
      warmupRuns: 0,
      measuredRuns: 3,
      bootstrapIterations: 250,
      observations: observations
    )
    let reverse = PrivateHoldoutAggregator.makeReport(
      corpusSchemaVersion: 1,
      caseCount: 5,
      warmupRuns: 0,
      measuredRuns: 3,
      bootstrapIterations: 250,
      observations: Array(observations.reversed())
    )
    #expect(forward == reverse)
    #expect(forward.bootstrap.iterations == 250)
    #expect(forward.bootstrap.confidenceLevel == 0.95)
  }

  @Test("Private evidence gates fail closed")
  func privateEvidenceGatesFailClosed() {
    let insufficient = PrivateHoldoutAggregator.makeReport(
      corpusSchemaVersion: 1,
      caseCount: 4,
      warmupRuns: 0,
      measuredRuns: 3,
      bootstrapIterations: 20,
      observations: privateObservations(caseCount: 4, targetedExecutions: 3)
    )
    #expect(insufficient.assessment == .insufficientNaturalExecutions)

    var regressed = privateObservations(caseCount: 4, targetedExecutions: 4)
    regressed[0].enabled.mismatchedFields = [CardField.emailAddresses.rawValue]
    let rejected = PrivateHoldoutAggregator.makeReport(
      corpusSchemaVersion: 1,
      caseCount: 4,
      warmupRuns: 0,
      measuredRuns: 3,
      bootstrapIterations: 20,
      observations: regressed
    )
    #expect(rejected.assessment == .rejectPolicyChange)
    #expect(rejected.pairedComparison.regressedFieldCount == 1)
  }

  @Test("Private manifest rejects path escape and unknown fields")
  func privateManifestBoundary() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0]).write(to: root.appendingPathComponent("sample.png"))

    let valid = try PrivateHoldoutManifest(
      data: privateManifestData(image: "sample.png", expectedKey: "emailAddresses"))
    #expect(try valid.validatedCases(root: root).count == 1)

    let escaping = try PrivateHoldoutManifest(
      data: privateManifestData(image: "../sample.png", expectedKey: "emailAddresses"))
    #expect(throws: PrivateHoldoutError.invalidImageReference) {
      try escaping.validatedCases(root: root)
    }

    let unknown = try PrivateHoldoutManifest(
      data: privateManifestData(image: "sample.png", expectedKey: "privateNote"))
    #expect(throws: PrivateHoldoutError.unknownExpectedField) {
      try unknown.validatedCases(root: root)
    }
  }

  @Test("Private runner uses the shipped threshold and three paired repeats")
  func privateRunnerExecutesTransientCorpus() throws {
    let scene = try #require(
      try TargetedStressManifest.load().first { $0.tags.contains("default-threshold") })
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let imageURL = root.appendingPathComponent("sample.png")
    try writePNG(try GoldenSceneRenderer.render(scene), to: imageURL)
    let manifest = try PrivateHoldoutManifest(
      data: try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1,
        "cases": [
          [
            "image": "sample.png",
            "expected": scene.expected,
            "recognitionLanguages": scene.profile.recognitionLanguages,
            "automaticallyDetectsLanguage": scene.profile.automaticallyDetectsLanguage,
            "attemptsCardIsolation": false,
          ]
        ],
      ]))
    let report = try PrivateHoldoutBenchmarkRunner(
      warmupRuns: 0,
      measuredRuns: 3,
      bootstrapIterations: 20
    ).run(manifest: manifest, root: root)

    #expect(report.caseCount == 1)
    #expect(report.measuredRuns == 3)
    #expect(report.configurations.allSatisfy { $0.sampleCount == 3 })
    #expect(report.assessment == .insufficientNaturalExecutions)
    let disabled = try #require(
      report.configurations.first { $0.configuration == .disabled })
    #expect(disabled.targetedExecutionRate == 0)
    #expect(disabled.targetedRequestCount.p95 == 0)
  }

  private func privateObservations(
    caseCount: Int,
    targetedExecutions: Int
  ) -> [PrivatePairedObservation] {
    (0..<caseCount).flatMap { caseIndex in
      (0..<3).map { run in
        let executes = caseIndex < targetedExecutions
        return PrivatePairedObservation(
          caseIndex: caseIndex,
          enabled: privateSample(
            total: Double(120 + caseIndex + run), targeted: executes ? 1 : 0),
          disabled: privateSample(total: Double(100 + caseIndex + run), targeted: 0)
        )
      }
    }
  }

  private func privateSample(total: Double, targeted: Int) -> TargetedBenchmarkSample {
    TargetedBenchmarkSample(
      diagnostics: AppleVisionScanDiagnostics(
        stageTimings: [AppleVisionStageTiming(stage: .total, durationMilliseconds: total)]
          + (targeted > 0
            ? [
              AppleVisionStageTiming(
                stage: .targetedReRecognition,
                durationMilliseconds: total / 3
              )
            ] : []),
        totalVisionRequestCount: 2 + targeted,
        rectangleRequestCount: 0,
        saliencyRequestCount: 0,
        textRecognitionRequestCount: 2 + targeted,
        primaryTextRecognitionRequestCount: 1 + targeted,
        secondaryTextRecognitionRequestCount: 1,
        targetedReRecognitionRequestCount: targeted,
        dualPassConfigured: true,
        dualPassExecuted: true,
        targetedReRecognitionConfigured: targeted > 0,
        targetedReRecognitionExecuted: targeted > 0,
        cardIsolationConfigured: true,
        cardIsolationAttempted: true,
        cardIsolationSucceeded: true,
        fullImageFallbackUsed: false
      ),
      mismatchedFields: [],
      supportedFields: [CardField.emailAddresses.rawValue],
      falseClearFields: [],
      reviewRecommended: false
    )
  }

  private func privateManifestData(image: String, expectedKey: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "cases": [
        [
          "image": image,
          "expected": [expectedKey: ["person@private.example"]],
        ]
      ],
    ])
  }

  private func writePNG(_ image: CGImage, to url: URL) throws {
    let destination = try #require(
      CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
  }
#else
  @Test("Private holdout benchmarking requires Apple Vision")
  func privateHoldoutBenchmarkUnavailable() {}
#endif
