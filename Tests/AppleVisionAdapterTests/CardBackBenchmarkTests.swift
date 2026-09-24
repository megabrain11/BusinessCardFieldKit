import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionAdapter
@testable import AppleVisionBenchmarking

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreImage
  import ImageIO
  import UniformTypeIdentifiers

  @Test("Synthetic card-back corpus reproduces payloads, fields, and merge decisions")
  func cardBackCorpusRegression() throws {
    let manifest = try cardBackManifest()
    let report = try CardBackBenchmarkRunner(warmupRuns: 0, measuredRuns: 1)
      .run(manifest: manifest)

    #expect(report.caseCount == 14)
    #expect(report.expectedBarcodeCount == 16)
    #expect(report.detectedBarcodeCount == 16)
    #expect(report.barcodeDetectionRate == 1)
    #expect(report.payloadKindAccuracyRate == 1)
    #expect(report.backFieldExactRate == 1)
    #expect(report.mergedFieldExactRate == 1)
    #expect(report.duplicateFreeRate == 1)
    #expect(report.reviewDecisionAccuracyRate == 1)
    #expect(report.cardRegionDecisionAccuracyRate == 1)
    let diagnostics = try #require(report.diagnosticsSummary)
    #expect(diagnostics.diagnosticSampleCount == 14)
    #expect(diagnostics.isolatedMaskSampleCount == 2)
    #expect(diagnostics.sourceBarcodeRequests.p50 == 1)
    #expect(diagnostics.sourceBarcodeRequests.p95 == 1)
    #expect(diagnostics.totalBarcodeRequests.p95 == 2)
    let maskTiming = try #require(
      diagnostics.stageDurations.first { $0.stage == .isolatedMaskDetection }
    )
    #expect(maskTiming.durationMilliseconds.sampleCount == 2)
    #expect(report.evidenceAssessment == .syntheticOnly)
  }

  @Test("Card-back renderer is deterministic and manifest remains fictional")
  func cardBackCorpusHygiene() throws {
    let manifest = try cardBackManifest()
    #expect(Set(manifest.cases.map(\.identifier)).count == manifest.cases.count)
    #expect(manifest.cases.allSatisfy { !$0.payloads.isEmpty })
    #expect(manifest.cases.allSatisfy { !$0.tags.isEmpty })

    let knownFields = Set(CardField.allCases.map(\.rawValue))
    for record in manifest.cases {
      let first = try CardBackSceneRenderer.render(record)
      let second = try CardBackSceneRenderer.render(record)
      #expect(pixelData(first) == pixelData(second))
      #expect(Set(record.backExpected.keys).isSubset(of: knownFields))
      #expect(Set(record.mergedExpected.keys).isSubset(of: knownFields))
      let frontKeys = Set(record.front?.keys.map { $0 } ?? [])
      #expect(frontKeys.isSubset(of: knownFields))

      var values: [String] = record.payloads.map(\.value)
      values += record.auxiliaryLines ?? []
      values += record.backExpected.values.flatMap { $0 }
      values += record.mergedExpected.values.flatMap { $0 }
      values += record.front?.values.flatMap { $0 } ?? []
      let folded = values.joined(separator: "\n").lowercased()
      #expect(!folded.contains("/" + "users/"))
      for value in values where value.contains("@") {
        #expect(value.lowercased().contains("example."))
      }
    }
  }

  @Test("Card-back reports are aggregate-only and independent of sample order")
  func cardBackReportRedactionAndDeterminism() throws {
    let samples = [
      CardBackBenchmarkSample(
        expectedBarcodeCount: 1, detectedBarcodeCount: 1, payloadKindsExact: true,
        backFieldsExact: true, mergedFieldsExact: true, duplicateFree: true,
        reviewDecisionExact: true, cardRegionDecisionExact: true,
        durationMilliseconds: 20, tags: ["vcard"],
        diagnostics: benchmarkDiagnostics(source: 1, mask: 0, sourceDuration: 2)),
      CardBackBenchmarkSample(
        expectedBarcodeCount: 2, detectedBarcodeCount: 1, payloadKindsExact: false,
        backFieldsExact: false, mergedFieldsExact: false, duplicateFree: true,
        reviewDecisionExact: false, cardRegionDecisionExact: false,
        durationMilliseconds: 10, tags: ["multiple"],
        diagnostics: benchmarkDiagnostics(source: 1, mask: 1, sourceDuration: 4)),
    ]
    let forward = CardBackBenchmarkAggregator.report(
      corpusSchemaVersion: 1, corpusVersion: "card-back-synthetic-1", caseCount: 2,
      warmupRuns: 0, measuredRuns: 1, assessment: .syntheticOnly, samples: samples)
    let reverse = CardBackBenchmarkAggregator.report(
      corpusSchemaVersion: 1, corpusVersion: "card-back-synthetic-1", caseCount: 2,
      warmupRuns: 0, measuredRuns: 1, assessment: .syntheticOnly,
      samples: Array(samples.reversed()))
    #expect(forward == reverse)
    #expect(forward.diagnosticsSummary?.diagnosticSampleCount == 2)
    #expect(forward.diagnosticsSummary?.isolatedMaskSampleCount == 1)

    let data = try JSONEncoder().encode(forward)
    let json = try #require(String(data: data, encoding: .utf8))
    for forbidden in [
      "BEGIN:VCARD", "private.person@", "caseIdentifier", "imagePath",
      "imageReference", "ocrText", "tokenValue", "/" + "Users/",
    ] {
      #expect(!json.localizedCaseInsensitiveContains(forbidden))
    }

    var legacyObject = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    legacyObject["reportSchemaVersion"] = 2
    legacyObject.removeValue(forKey: "diagnosticsSummary")
    let legacy = try JSONDecoder().decode(
      CardBackBenchmarkReport.self,
      from: JSONSerialization.data(withJSONObject: legacyObject)
    )
    #expect(legacy.reportSchemaVersion == 2)
    #expect(legacy.diagnosticsSummary == nil)
  }

  @Test("Card-back text classification masks QR regions only in shared coordinates")
  func barcodeRegionMasking() {
    let inside = OCRToken(
      id: "inside", text: "noise",
      boundingBox: NormalizedBoundingBox(x: 0.4, y: 0.4, width: 0.1, height: 0.1),
      confidence: 0.8)
    let outside = OCRToken(
      id: "outside", text: "person@example.net",
      boundingBox: NormalizedBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.05),
      confidence: 0.9)
    let barcode = NormalizedBoundingBox(x: 0.35, y: 0.35, width: 0.3, height: 0.3)

    let filtered = CardBackScanner.tokensOutsideBarcodeRegions(
      [inside, outside], barcodeRegions: [barcode])
    #expect(filtered.map(\.id) == ["outside"])

    let isolated = CardBackScanner.tokensOutsideBarcodeRegions(
      [inside, outside],
      barcodeRegions: [barcode]
    )
    #expect(isolated.map(\.id) == ["outside"])
  }

  @Test("Perspective-isolated backs preserve nearby text and suppress QR OCR noise")
  func isolatedPerspectiveBarcodeMasking() throws {
    let record = try #require(
      try cardBackManifest().cases.first {
        $0.identifier == "back-isolated-perspective-nearby-text"
      }
    )
    let image = try CardBackSceneRenderer.render(record)
    let configuration = CardBackBenchmarkRunner.scanConfiguration(
      attemptsCardIsolation: true
    )
    let result = try CardBackScanner(configuration: configuration).scan(cgImage: image)

    guard case .isolated = result.cardRegionSelection else {
      Issue.record("Expected the synthetic perspective card to be isolated")
      return
    }
    #expect(result.detectedBarcodes.map(\.payloadKind) == [.unsupported])
    #expect(result.fields.fullName == nil)
    #expect(result.fields.organization == nil)
    #expect(result.fields.emailAddresses.map(\.normalizedValue) == ["nearby@example.net"])
    #expect(
      result.fields.workPhoneNumbers.map { $0.normalizedValue.filter(\.isNumber) }
        == ["12025550191"]
    )
  }

  @Test("Prepared token scan preserves the public token result contract")
  func preparedTokenScanParity() throws {
    let record = try #require(
      try cardBackManifest().cases.first {
        $0.identifier == "back-isolated-perspective-nearby-text"
      }
    )
    let image = try CardBackSceneRenderer.render(record)
    let scanner = AppleVisionScanner(
      configuration: CardBackBenchmarkRunner.scanConfiguration(
        attemptsCardIsolation: true
      )
    )

    let publicResult = try scanner.scanTokens(cgImage: image)
    let prepared = try scanner.scanTokensWithRecognitionImage(cgImage: image)

    #expect(prepared.result == publicResult)
    #expect(prepared.recognitionImage.width > 0)
    #expect(prepared.recognitionImage.height > 0)
    guard case .isolated = prepared.result.cardRegionSelection else {
      Issue.record("Expected a perspective-corrected recognition image")
      return
    }
  }

  @Test("EXIF rotation keeps isolated barcode masking and fields stable")
  func isolatedPerspectiveEXIFParity() throws {
    let record = try #require(
      try cardBackManifest().cases.first {
        $0.identifier == "back-isolated-perspective-nearby-text"
      }
    )
    let upright = try CardBackSceneRenderer.render(record)
    let configuration = CardBackBenchmarkRunner.scanConfiguration(
      attemptsCardIsolation: true
    )
    let scanner = CardBackScanner(configuration: configuration)
    let baseline = try scanner.scan(cgImage: upright)
    let stored = try #require(
      CIContext().createCGImage(
        CIImage(cgImage: upright).oriented(.left),
        from: CIImage(cgImage: upright).oriented(.left).extent
      )
    )
    let encoded = try encodedJPEG(stored, orientation: .right)
    let oriented = try scanner.scan(imageData: encoded)

    #expect(oriented.fields == baseline.fields)
    #expect(
      oriented.detectedBarcodes.map(\.payloadKind)
        == baseline.detectedBarcodes.map(\.payloadKind)
    )
    guard case .isolated = oriented.cardRegionSelection else {
      Issue.record("Expected EXIF-oriented card isolation")
      return
    }
  }

  @Test("Private card-back manifest fails closed at the corpus boundary")
  func privateCardBackManifestBoundary() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0]).write(to: root.appendingPathComponent("sample.png"))

    let valid = try PrivateCardBackManifest(
      data: privateManifestData(image: "sample.png", expectedKey: "websites"))
    #expect(try valid.validatedCases(root: root).count == 1)

    let escaping = try PrivateCardBackManifest(
      data: privateManifestData(image: "../sample.png", expectedKey: "websites"))
    #expect(throws: CardBackBenchmarkError.invalidImageReference) {
      try escaping.validatedCases(root: root)
    }

    let unknown = try PrivateCardBackManifest(
      data: privateManifestData(image: "sample.png", expectedKey: "privateNote"))
    #expect(throws: CardBackBenchmarkError.unknownExpectedField) {
      try unknown.validatedCases(root: root)
    }
  }

  @Test("Private card-back runner emits repeat-only aggregate evidence")
  func privateCardBackRunner() throws {
    let synthetic = try #require(try cardBackManifest().cases.first)
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try writePNG(
      CardBackSceneRenderer.render(synthetic),
      to: root.appendingPathComponent("sample.png"))
    let manifest = try PrivateCardBackManifest(
      data: privateManifestData(
        image: "sample.png",
        expectedPayloadKinds: synthetic.expectedPayloadKinds.map(\.rawValue),
        backExpected: synthetic.backExpected,
        mergedExpected: synthetic.mergedExpected,
        reviewExpected: synthetic.reviewExpected
      ))
    let report = try PrivateCardBackBenchmarkRunner(warmupRuns: 0, measuredRuns: 3)
      .run(manifest: manifest, root: root)

    #expect(report.caseCount == 1)
    #expect(report.measuredRuns == 3)
    #expect(report.expectedBarcodeCount == 3)
    #expect(report.corpusVersion == nil)
    #expect(report.tagCoverage.isEmpty)
    #expect(report.evidenceAssessment == .privateAggregateAvailable)
    #expect(report.barcodeDetectionRate == 1)
    #expect(report.backFieldExactRate == 1)

    let envelope = PrivateCardBackCommandReport.completed(report)
    let json = try #require(String(data: JSONEncoder().encode(envelope), encoding: .utf8))
    #expect(!json.contains("sample.png"))
    #expect(!json.contains("Alex Kim"))
    #expect(!json.contains("alex.kim@example.com"))

    let skipped = try #require(
      String(data: JSONEncoder().encode(PrivateCardBackCommandReport.skipped), encoding: .utf8))
    #expect(skipped.contains("privateCorpusUnavailable"))
    #expect(!skipped.contains("PRIVATE_CARD_BACK_CORPUS_ROOT"))
  }

  @Test("Private projective masking experiment emits redacted paired evidence")
  func privateProjectiveMaskingExperiment() throws {
    let synthetic = try #require(
      try cardBackManifest().cases.first {
        $0.identifier == "back-isolated-perspective-nearby-text"
      }
    )
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try writePNG(
      CardBackSceneRenderer.render(synthetic),
      to: root.appendingPathComponent("private-scene.png")
    )
    let manifest = try PrivateCardBackManifest(
      data: privateManifestData(
        image: "private-scene.png",
        expectedPayloadKinds: synthetic.expectedPayloadKinds.map(\.rawValue),
        backExpected: synthetic.backExpected,
        mergedExpected: synthetic.mergedExpected,
        reviewExpected: synthetic.reviewExpected,
        attemptsCardIsolation: true
      )
    )
    let comparison = try PrivateCardBackBenchmarkRunner(warmupRuns: 0, measuredRuns: 3)
      .runMaskingExperiment(manifest: manifest, root: root)

    #expect(comparison.caseCount == 1)
    #expect(comparison.measuredRuns == 3)
    #expect(comparison.corpusVersion == nil)
    #expect(comparison.evidenceAssessment == .privateAggregateAvailable)
    #expect(comparison.resultParityRate == 1)
    #expect(comparison.tokenParityRate == 1)
    #expect(comparison.fieldParityRate == 1)
    #expect(comparison.barcodeParityRate == 1)
    #expect(comparison.cardRegionParityRate == 1)
    #expect(comparison.isolatedSampleCount == 3)
    #expect(comparison.projectiveMaskingAppliedSampleCount == 3)
    #expect(comparison.projectiveMaskFallbackCount == 0)
    #expect(comparison.isolatedBarcodeRequestReduction.p50 == 1)
    #expect(comparison.isolatedBarcodeRequestReduction.p95 == 1)
    #expect(comparison.durationDeltaMilliseconds.sampleCount == 3)

    let envelope = PrivateCardBackCommandReport.completedMaskingComparison(comparison)
    let json = try #require(String(data: JSONEncoder().encode(envelope), encoding: .utf8))
    #expect(!json.contains("private-scene.png"))
    #expect(!json.contains("nearby@example.net"))
    #expect(!json.contains(root.path))
    #expect(!json.contains("PRIVATE_CARD_BACK_CORPUS_ROOT"))
    #expect(json.contains("privateAggregateAvailable"))
  }

  @Test("Private report decodes legacy envelopes without masking comparison")
  func privateReportLegacyDecoding() throws {
    let data = Data(
      """
      {"reportSchemaVersion":1,"status":"skipped","skipReason":"privateCorpusUnavailable"}
      """.utf8
    )
    let report = try JSONDecoder().decode(PrivateCardBackCommandReport.self, from: data)
    #expect(report.reportSchemaVersion == 1)
    #expect(report.status == .skipped)
    #expect(report.skipReason == .privateCorpusUnavailable)
    #expect(report.report == nil)
    #expect(report.maskingComparison == nil)
    #expect(report.barcodeRecoveryComparison == nil)
  }

  @Test("Private projective masking experiment requires three measured runs")
  func privateProjectiveMaskingRunCount() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0]).write(to: root.appendingPathComponent("sample.png"))
    let manifest = try PrivateCardBackManifest(
      data: privateManifestData(image: "sample.png", expectedKey: "websites")
    )
    #expect(throws: CardBackBenchmarkError.invalidRunCount) {
      try PrivateCardBackBenchmarkRunner(warmupRuns: 0, measuredRuns: 2)
        .runMaskingExperiment(manifest: manifest, root: root)
    }
  }

  private func cardBackManifest() throws -> CardBackCorpusManifest {
    try CardBackCorpusManifest(
      data: Data(
        contentsOf: repositoryRoot.appendingPathComponent("Fixtures/CardBack/manifest.json")
      )
    )
  }

  private func benchmarkDiagnostics(
    source: Int,
    mask: Int,
    sourceDuration: Double
  ) -> AppleVisionBackScanDiagnostics {
    var timings = [
      AppleVisionBackStageTiming(
        stage: .sourceBarcodeDetection,
        durationMilliseconds: sourceDuration
      ),
      AppleVisionBackStageTiming(stage: .tokenRecognition, durationMilliseconds: 5),
    ]
    if mask > 0 {
      timings.append(
        AppleVisionBackStageTiming(stage: .isolatedMaskDetection, durationMilliseconds: 3)
      )
    }
    timings.append(
      AppleVisionBackStageTiming(stage: .classificationAndMerge, durationMilliseconds: 1)
    )
    timings.append(AppleVisionBackStageTiming(stage: .total, durationMilliseconds: 10))
    return AppleVisionBackScanDiagnostics(
      stageTimings: timings,
      totalBarcodeRequestCount: source + mask,
      sourceBarcodeRequestCount: source,
      isolatedMaskBarcodeRequestCount: mask,
      isolatedMaskDetectionExecuted: mask > 0
    )
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func pixelData(_ image: CGImage) -> Data? {
    image.dataProvider?.data as Data?
  }

  private func privateManifestData(image: String, expectedKey: String) throws -> Data {
    try privateManifestData(
      image: image,
      expectedPayloadKinds: ["url"],
      backExpected: [expectedKey: ["https://private.example/card"]],
      mergedExpected: [expectedKey: ["https://private.example/card"]],
      reviewExpected: false
    )
  }

  private func privateManifestData(
    image: String,
    expectedPayloadKinds: [String],
    backExpected: [String: [String]],
    mergedExpected: [String: [String]],
    reviewExpected: Bool,
    attemptsCardIsolation: Bool = false
  ) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "cases": [
        [
          "image": image,
          "expectedPayloadKinds": expectedPayloadKinds,
          "backExpected": backExpected,
          "mergedExpected": mergedExpected,
          "reviewExpected": reviewExpected,
          "attemptsCardIsolation": attemptsCardIsolation,
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

  private func encodedJPEG(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation
  ) throws -> Data {
    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(
        data,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    )
    let properties: [CFString: Any] = [
      kCGImagePropertyOrientation: orientation.rawValue,
      kCGImageDestinationLossyCompressionQuality: 1.0,
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }
#else
  @Test("Card-back benchmarking requires Apple Vision")
  func cardBackBenchmarkUnavailable() {}
#endif
