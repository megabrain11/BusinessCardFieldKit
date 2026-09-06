import AppleVisionAdapter
import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import CoreImage
  import CoreText

  public struct CardBackCorpusManifest: Decodable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var corpusVersion: String
    public var cases: [CardBackCorpusCase]

    public init(data: Data) throws {
      self = try JSONDecoder().decode(Self.self, from: data)
      guard schemaVersion == Self.currentSchemaVersion else {
        throw CardBackBenchmarkError.unsupportedSchemaVersion
      }
      guard !cases.isEmpty else { throw CardBackBenchmarkError.emptyCorpus }
      let identifiers = cases.map(\.identifier)
      guard Set(identifiers).count == identifiers.count else {
        throw CardBackBenchmarkError.duplicateIdentifier
      }
    }
  }

  public struct CardBackCorpusCase: Decodable, Sendable {
    public var identifier: String
    public var layout: CardBackLayout
    public var payloads: [CardBackPayload]
    public var auxiliaryLines: [String]?
    public var attemptsCardIsolation: Bool?
    public var tags: [String]
    public var expectedPayloadKinds: [AppleVisionDetectedBarcode.PayloadKind]
    public var backExpected: [String: [String]]
    public var front: [String: [String]]?
    public var mergedExpected: [String: [String]]
    public var reviewExpected: Bool
  }

  public struct CardBackPayload: Decodable, Sendable {
    public var value: String
  }

  public enum CardBackLayout: String, Decodable, Sendable {
    case standard
    case small
    case tiny
    case lowContrast
    case veryLowContrast
    case blurred
    case centerOverlay
    case dotStyle
    case rotated
    case perspective
    case strongPerspective
    case multiple
    case textAndQR
    case isolatedPerspective
  }

  public enum CardBackBenchmarkError: Error, Equatable {
    case unsupportedSchemaVersion
    case emptyCorpus
    case duplicateIdentifier
    case invalidRunCount
    case failedToCreateImage
    case invalidImageReference
    case duplicateImageReference
    case imageOutsideCorpusRoot
    case imageUnavailable
    case unknownExpectedField
  }

  public enum CardBackSceneRenderer {
    public static func render(_ record: CardBackCorpusCase) throws -> CGImage {
      if record.layout == .isolatedPerspective {
        return try renderIsolatedPerspective(record)
      }
      let canvasSize = CGSize(width: 1_200, height: 800)
      guard
        let context = CGContext(
          data: nil,
          width: Int(canvasSize.width),
          height: Int(canvasSize.height),
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { throw CardBackBenchmarkError.failedToCreateImage }
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(origin: .zero, size: canvasSize))

      let frames = frames(for: record.layout, count: record.payloads.count)
      for pair in zip(record.payloads, frames) {
        let (payload, frame) = pair
        let qr = try styledQRCode(
          payload.value,
          layout: record.layout
        )
        draw(qr, in: frame, layout: record.layout, context: context)
        if record.layout == .centerOverlay {
          let side = frame.width * 0.36
          let overlay = CGRect(
            x: frame.midX - side / 2,
            y: frame.midY - side / 2,
            width: side,
            height: side
          )
          context.setFillColor(CGColor(gray: 0.96, alpha: 1))
          context.fillEllipse(in: overlay)
          context.setStrokeColor(CGColor(gray: 0.25, alpha: 1))
          context.setLineWidth(4)
          context.strokeEllipse(in: overlay.insetBy(dx: 3, dy: 3))
        }
      }
      if !(record.auxiliaryLines ?? []).isEmpty {
        drawLines(record.auxiliaryLines ?? [], in: context, canvasSize: canvasSize)
      }
      guard let image = context.makeImage() else {
        throw CardBackBenchmarkError.failedToCreateImage
      }
      return image
    }

    private static func frames(for layout: CardBackLayout, count: Int) -> [CGRect] {
      if layout == .multiple {
        let base = [
          CGRect(x: 90, y: 210, width: 340, height: 340),
          CGRect(x: 760, y: 210, width: 340, height: 340),
        ]
        return Array(base.prefix(count))
      }
      let frame: CGRect
      switch layout {
      case .small:
        frame = CGRect(x: 485, y: 285, width: 230, height: 230)
      case .tiny:
        frame = CGRect(x: 570, y: 370, width: 60, height: 60)
      case .veryLowContrast:
        frame = CGRect(x: 510, y: 310, width: 180, height: 180)
      case .blurred:
        frame = CGRect(x: 520, y: 320, width: 160, height: 160)
      case .centerOverlay, .dotStyle, .strongPerspective:
        frame = CGRect(x: 460, y: 260, width: 280, height: 280)
      case .textAndQR:
        frame = CGRect(x: 745, y: 190, width: 390, height: 390)
      case .standard, .lowContrast, .rotated, .perspective, .multiple,
        .isolatedPerspective:
        frame = CGRect(x: 370, y: 170, width: 460, height: 460)
      }
      return Array(repeating: frame, count: count)
    }

    private static func styledQRCode(
      _ payload: String,
      layout: CardBackLayout
    ) throws -> CGImage {
      let colors: (dark: CGFloat, light: CGFloat)
      switch layout {
      case .lowContrast:
        colors = (0.42, 0.92)
      case .veryLowContrast:
        colors = (0.66, 0.76)
      default:
        colors = (0, 1)
      }
      var image = CIImage(
        cgImage: try qrCode(
          payload,
          darkGray: colors.dark,
          lightGray: colors.light
        )
      )
      let originalExtent = image.extent
      if layout == .dotStyle {
        image = image.applyingFilter(
          "CIMorphologyMaximum",
          parameters: ["inputRadius": 4.5]
        ).cropped(to: originalExtent)
      } else if layout == .blurred {
        image = image.applyingFilter(
          "CIGaussianBlur",
          parameters: [kCIInputRadiusKey: 3.4]
        ).cropped(to: originalExtent)
      }
      guard let output = CIContext().createCGImage(image, from: originalExtent.integral) else {
        throw CardBackBenchmarkError.failedToCreateImage
      }
      return output
    }

    private static func qrCode(
      _ payload: String,
      darkGray: CGFloat,
      lightGray: CGFloat
    ) throws -> CGImage {
      guard let generator = CIFilter(name: "CIQRCodeGenerator") else {
        throw CardBackBenchmarkError.failedToCreateImage
      }
      generator.setValue(Data(payload.utf8), forKey: "inputMessage")
      generator.setValue("H", forKey: "inputCorrectionLevel")
      guard var output = generator.outputImage else {
        throw CardBackBenchmarkError.failedToCreateImage
      }
      if darkGray != 0 || lightGray != 1 {
        output = output.applyingFilter(
          "CIFalseColor",
          parameters: [
            "inputColor0": CIColor(red: darkGray, green: darkGray, blue: darkGray),
            "inputColor1": CIColor(red: lightGray, green: lightGray, blue: lightGray),
          ]
        )
      }
      let scale = floor(480 / max(output.extent.width, 1))
      output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      guard let image = CIContext().createCGImage(output, from: output.extent.integral) else {
        throw CardBackBenchmarkError.failedToCreateImage
      }
      return image
    }

    private static func draw(
      _ image: CGImage,
      in frame: CGRect,
      layout: CardBackLayout,
      context: CGContext
    ) {
      context.saveGState()
      if layout == .rotated {
        context.translateBy(x: frame.midX, y: frame.midY)
        context.rotate(by: 12 * .pi / 180)
        context.draw(
          image,
          in: CGRect(
            x: -frame.width / 2, y: -frame.height / 2, width: frame.width, height: frame.height))
      } else if layout == .perspective {
        context.draw(perspectiveImage(image) ?? image, in: frame)
      } else if layout == .strongPerspective {
        context.draw(strongPerspectiveImage(image) ?? image, in: frame)
      } else {
        context.draw(image, in: frame)
      }
      context.restoreGState()
    }

    private static func strongPerspectiveImage(_ image: CGImage) -> CGImage? {
      let input = CIImage(cgImage: image)
      let extent = input.extent
      let output = input.applyingFilter(
        "CIPerspectiveTransform",
        parameters: [
          "inputTopLeft": CIVector(
            x: extent.minX + extent.width * 0.28,
            y: extent.maxY - extent.height * 0.04
          ),
          "inputTopRight": CIVector(
            x: extent.maxX - extent.width * 0.02,
            y: extent.maxY - extent.height * 0.38
          ),
          "inputBottomRight": CIVector(
            x: extent.maxX - extent.width * 0.28,
            y: extent.minY + extent.height * 0.18
          ),
          "inputBottomLeft": CIVector(
            x: extent.minX + extent.width * 0.02,
            y: extent.minY + extent.height * 0.02
          ),
        ]
      )
      return CIContext().createCGImage(output, from: output.extent.integral)
    }

    private static func perspectiveImage(_ image: CGImage) -> CGImage? {
      let input = CIImage(cgImage: image)
      let extent = input.extent
      let output = input.applyingFilter(
        "CIPerspectiveTransform",
        parameters: [
          "inputTopLeft": CIVector(x: extent.minX + extent.width * 0.08, y: extent.maxY),
          "inputTopRight": CIVector(x: extent.maxX, y: extent.maxY - extent.height * 0.10),
          "inputBottomRight": CIVector(
            x: extent.maxX - extent.width * 0.06, y: extent.minY + extent.height * 0.06),
          "inputBottomLeft": CIVector(x: extent.minX, y: extent.minY),
        ]
      )
      return CIContext().createCGImage(output, from: output.extent.integral)
    }

    private static func drawLines(
      _ lines: [String],
      in context: CGContext,
      canvasSize: CGSize
    ) {
      let font = CTFontCreateWithName("Helvetica" as CFString, 34, nil)
      let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(gray: 0.08, alpha: 1),
      ]
      for (index, line) in lines.enumerated() {
        guard
          let attributed = CFAttributedStringCreate(
            nil, line as CFString, attributes as CFDictionary)
        else { continue }
        context.textPosition = CGPoint(x: 70, y: canvasSize.height - 180 - CGFloat(index * 70))
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
      }
    }

    /// Renders the complete card first and then applies one projective transform
    /// to the card, its text, and every QR code. This is the regression case for
    /// OCR/barcode coordinates after automatic card isolation.
    private static func renderIsolatedPerspective(
      _ record: CardBackCorpusCase
    ) throws -> CGImage {
      let cardSize = CGSize(width: 1_000, height: 560)
      guard
        let cardContext = CGContext(
          data: nil,
          width: Int(cardSize.width),
          height: Int(cardSize.height),
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { throw CardBackBenchmarkError.failedToCreateImage }
      cardContext.setFillColor(CGColor(gray: 0.98, alpha: 1))
      cardContext.fill(CGRect(origin: .zero, size: cardSize))
      drawLines(record.auxiliaryLines ?? [], in: cardContext, canvasSize: cardSize)

      let qrFrames: [CGRect]
      if record.payloads.count > 1 {
        qrFrames = [
          CGRect(x: 500, y: 150, width: 220, height: 220),
          CGRect(x: 750, y: 150, width: 220, height: 220),
        ]
      } else {
        qrFrames = [CGRect(x: 570, y: 85, width: 410, height: 410)]
      }
      for (payload, frame) in zip(record.payloads, qrFrames) {
        cardContext.draw(
          try qrCode(payload.value, darkGray: 0, lightGray: 1),
          in: frame
        )
      }
      guard let card = cardContext.makeImage() else {
        throw CardBackBenchmarkError.failedToCreateImage
      }

      let canvasExtent = CGRect(x: 0, y: 0, width: 1_400, height: 900)
      let input = CIImage(cgImage: card)
      let warped = input.applyingFilter(
        "CIPerspectiveTransform",
        parameters: [
          "inputTopLeft": CIVector(x: 175, y: 780),
          "inputTopRight": CIVector(x: 1_255, y: 715),
          "inputBottomRight": CIVector(x: 1_180, y: 145),
          "inputBottomLeft": CIVector(x: 105, y: 215),
        ]
      )
      let background = CIImage(color: CIColor(red: 0.15, green: 0.17, blue: 0.20))
        .cropped(to: canvasExtent)
      let scene = warped.composited(over: background).cropped(to: canvasExtent)
      guard let image = CIContext().createCGImage(scene, from: canvasExtent) else {
        throw CardBackBenchmarkError.failedToCreateImage
      }
      return image
    }
  }

  public struct CardBackTagCoverage: Codable, Equatable, Sendable {
    public var tag: String
    public var sampleCount: Int
  }

  public struct CardBackBenchmarkStageSummary: Codable, Equatable, Sendable {
    public var stage: AppleVisionBackScanStage
    public var durationMilliseconds: BenchmarkDistribution
  }

  /// Aggregate-only summary of the opt-in card-back diagnostics payloads.
  public struct CardBackDiagnosticsSummary: Codable, Equatable, Sendable {
    public var diagnosticSampleCount: Int
    public var isolatedMaskSampleCount: Int
    public var stageDurations: [CardBackBenchmarkStageSummary]
    public var totalBarcodeRequests: BenchmarkDistribution
    public var sourceBarcodeRequests: BenchmarkDistribution
    public var isolatedMaskBarcodeRequests: BenchmarkDistribution
  }

  /// Aggregate-only card-back report with no payload, OCR text, path, image, or case identifier.
  public struct CardBackBenchmarkReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public var reportSchemaVersion: Int
    public var corpusSchemaVersion: Int
    public var corpusVersion: String?
    public var caseCount: Int
    public var warmupRuns: Int
    public var measuredRuns: Int
    public var expectedBarcodeCount: Int
    public var detectedBarcodeCount: Int
    public var barcodeDetectionRate: Double
    public var payloadKindAccuracyRate: Double
    public var backFieldExactRate: Double
    public var mergedFieldExactRate: Double
    public var duplicateFreeRate: Double
    public var reviewDecisionAccuracyRate: Double
    public var cardRegionDecisionAccuracyRate: Double
    public var totalDurationMilliseconds: BenchmarkDistribution
    public var diagnosticsSummary: CardBackDiagnosticsSummary?
    public var tagCoverage: [CardBackTagCoverage]
    public var evidenceAssessment: CardBackEvidenceAssessment
    public var evidenceLimitations: [String]
  }

  public enum CardBackEvidenceAssessment: String, Codable, Sendable {
    case syntheticOnly
    case insufficientEvidence
    case privateAggregateAvailable
  }

  public struct CardBackBenchmarkSample: Equatable, Sendable {
    public var expectedBarcodeCount: Int
    public var detectedBarcodeCount: Int
    public var payloadKindsExact: Bool
    public var backFieldsExact: Bool
    public var mergedFieldsExact: Bool
    public var duplicateFree: Bool
    public var reviewDecisionExact: Bool
    public var cardRegionDecisionExact: Bool
    public var durationMilliseconds: Double
    public var tags: [String]
    public var diagnostics: AppleVisionBackScanDiagnostics?

    public init(
      expectedBarcodeCount: Int,
      detectedBarcodeCount: Int,
      payloadKindsExact: Bool,
      backFieldsExact: Bool,
      mergedFieldsExact: Bool,
      duplicateFree: Bool,
      reviewDecisionExact: Bool,
      cardRegionDecisionExact: Bool,
      durationMilliseconds: Double,
      tags: [String],
      diagnostics: AppleVisionBackScanDiagnostics? = nil
    ) {
      self.expectedBarcodeCount = max(expectedBarcodeCount, 0)
      self.detectedBarcodeCount = max(detectedBarcodeCount, 0)
      self.payloadKindsExact = payloadKindsExact
      self.backFieldsExact = backFieldsExact
      self.mergedFieldsExact = mergedFieldsExact
      self.duplicateFree = duplicateFree
      self.reviewDecisionExact = reviewDecisionExact
      self.cardRegionDecisionExact = cardRegionDecisionExact
      self.durationMilliseconds = max(durationMilliseconds, 0)
      self.tags = Array(Set(tags)).sorted()
      self.diagnostics = diagnostics
    }
  }

  public enum CardBackBenchmarkAggregator {
    public static func report(
      corpusSchemaVersion: Int,
      corpusVersion: String?,
      caseCount: Int,
      warmupRuns: Int,
      measuredRuns: Int,
      assessment: CardBackEvidenceAssessment,
      samples: [CardBackBenchmarkSample]
    ) -> CardBackBenchmarkReport {
      let expected = samples.reduce(0) { $0 + $1.expectedBarcodeCount }
      let detected = samples.reduce(0) {
        $0 + min($1.detectedBarcodeCount, $1.expectedBarcodeCount)
      }
      let tagCounts = Dictionary(
        grouping: samples.flatMap { sample in sample.tags },
        by: { $0 }
      )
      let diagnostics = samples.compactMap(\.diagnostics)
      return CardBackBenchmarkReport(
        reportSchemaVersion: CardBackBenchmarkReport.currentSchemaVersion,
        corpusSchemaVersion: corpusSchemaVersion,
        corpusVersion: corpusVersion,
        caseCount: caseCount,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        expectedBarcodeCount: expected,
        detectedBarcodeCount: detected,
        barcodeDetectionRate: rate(detected, expected),
        payloadKindAccuracyRate: rate(samples.filter(\.payloadKindsExact).count, samples.count),
        backFieldExactRate: rate(samples.filter(\.backFieldsExact).count, samples.count),
        mergedFieldExactRate: rate(samples.filter(\.mergedFieldsExact).count, samples.count),
        duplicateFreeRate: rate(samples.filter(\.duplicateFree).count, samples.count),
        reviewDecisionAccuracyRate: rate(
          samples.filter(\.reviewDecisionExact).count, samples.count),
        cardRegionDecisionAccuracyRate: rate(
          samples.filter(\.cardRegionDecisionExact).count, samples.count),
        totalDurationMilliseconds: BenchmarkDistribution(
          values: samples.map(\.durationMilliseconds)),
        diagnosticsSummary: diagnosticsSummary(diagnostics),
        tagCoverage: tagCounts.map {
          CardBackTagCoverage(tag: $0.key, sampleCount: $0.value.count)
        }.sorted { $0.tag < $1.tag },
        evidenceAssessment: assessment,
        evidenceLimitations: limitations(for: assessment)
      )
    }

    private static func diagnosticsSummary(
      _ diagnostics: [AppleVisionBackScanDiagnostics]
    ) -> CardBackDiagnosticsSummary? {
      guard !diagnostics.isEmpty else { return nil }
      let stages: [CardBackBenchmarkStageSummary] =
        AppleVisionBackScanStage.allCases.compactMap { stage in
          let values = diagnostics.compactMap { sample in
            sample.stageTimings.first { $0.stage == stage }?.durationMilliseconds
          }
          guard !values.isEmpty else { return nil }
          return CardBackBenchmarkStageSummary(
            stage: stage,
            durationMilliseconds: BenchmarkDistribution(values: values)
          )
        }
      return CardBackDiagnosticsSummary(
        diagnosticSampleCount: diagnostics.count,
        isolatedMaskSampleCount: diagnostics.filter(\.isolatedMaskDetectionExecuted).count,
        stageDurations: stages,
        totalBarcodeRequests: BenchmarkDistribution(
          values: diagnostics.map { Double($0.totalBarcodeRequestCount) }
        ),
        sourceBarcodeRequests: BenchmarkDistribution(
          values: diagnostics.map { Double($0.sourceBarcodeRequestCount) }
        ),
        isolatedMaskBarcodeRequests: BenchmarkDistribution(
          values: diagnostics.map { Double($0.isolatedMaskBarcodeRequestCount) }
        )
      )
    }

    private static func limitations(
      for assessment: CardBackEvidenceAssessment
    ) -> [String] {
      var values = [
        "Barcode timing varies with hardware, system load, and Vision runtime.",
        "Aggregate reports cannot identify an individual failing source.",
      ]
      switch assessment {
      case .syntheticOnly:
        values.insert(
          "Synthetic QR scenes do not establish physical-device or real-photo performance.",
          at: 0)
      case .insufficientEvidence:
        values.insert("No configured private corpus was evaluated.", at: 0)
      case .privateAggregateAvailable:
        values.append("Private aggregate evidence does not approve a production rollout.")
      }
      return values
    }

    private static func rate(_ numerator: Int, _ denominator: Int) -> Double {
      guard denominator > 0 else { return 0 }
      return Double(numerator) / Double(denominator)
    }
  }

  public struct CardBackBenchmarkRunner: Sendable {
    public var warmupRuns: Int
    public var measuredRuns: Int

    public init(warmupRuns: Int = 1, measuredRuns: Int = 3) {
      self.warmupRuns = warmupRuns
      self.measuredRuns = measuredRuns
    }

    public func run(manifest: CardBackCorpusManifest) throws -> CardBackBenchmarkReport {
      guard warmupRuns >= 0, measuredRuns > 0 else {
        throw CardBackBenchmarkError.invalidRunCount
      }
      for _ in 0..<warmupRuns {
        for record in manifest.cases {
          _ = try scan(record, image: CardBackSceneRenderer.render(record))
        }
      }
      var samples: [CardBackBenchmarkSample] = []
      for _ in 0..<measuredRuns {
        for record in manifest.cases {
          samples.append(try scan(record, image: CardBackSceneRenderer.render(record)))
        }
      }
      return CardBackBenchmarkAggregator.report(
        corpusSchemaVersion: manifest.schemaVersion,
        corpusVersion: manifest.corpusVersion,
        caseCount: manifest.cases.count,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
        assessment: .syntheticOnly,
        samples: samples
      )
    }

    func scan(
      _ record: CardBackCorpusCase,
      image: CGImage,
      maskingStrategy: AppleVisionBarcodeMaskingStrategy = .rectifiedRedetection
    ) throws -> CardBackBenchmarkSample {
      let measured = try scanResult(
        record,
        image: image,
        maskingStrategy: maskingStrategy
      )
      return Self.sample(
        detected: measured.result,
        expectedPayloadKinds: record.expectedPayloadKinds,
        backExpected: record.backExpected,
        front: record.front ?? [:],
        mergedExpected: record.mergedExpected,
        reviewExpected: record.reviewExpected,
        attemptsCardIsolation: measured.attemptsIsolation,
        durationMilliseconds: measured.durationMilliseconds,
        tags: record.tags
      )
    }

    func scanResult(
      _ record: CardBackCorpusCase,
      image: CGImage,
      maskingStrategy: AppleVisionBarcodeMaskingStrategy = .rectifiedRedetection,
      barcodeDetectionRecovery: AppleVisionBarcodeDetectionRecoveryOptions =
        AppleVisionBarcodeDetectionRecoveryOptions()
    ) throws -> (
      result: AppleVisionBackScanResult,
      durationMilliseconds: Double,
      attemptsIsolation: Bool
    ) {
      let start = ContinuousClock.now
      let attemptsIsolation = record.attemptsCardIsolation ?? false
      var configuration = Self.scanConfiguration(
        attemptsCardIsolation: attemptsIsolation,
        maskingStrategy: maskingStrategy,
        barcodeDetectionRecovery: barcodeDetectionRecovery
      )
      configuration.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
      let result = try CardBackScanner(
        configuration: configuration
      ).scan(cgImage: image)
      let duration = milliseconds(start.duration(to: .now))
      return (result, duration, attemptsIsolation)
    }

    static func sample(
      detected result: AppleVisionBackScanResult,
      expectedPayloadKinds: [AppleVisionDetectedBarcode.PayloadKind],
      backExpected: [String: [String]],
      front: [String: [String]],
      mergedExpected: [String: [String]],
      reviewExpected: Bool,
      attemptsCardIsolation: Bool,
      durationMilliseconds: Double,
      tags: [String]
    ) -> CardBackBenchmarkSample {
      let merged = CardScanSession().merge(
        front: Self.result(from: front), back: result.fields
      ).merged
      return CardBackBenchmarkSample(
        expectedBarcodeCount: expectedPayloadKinds.count,
        detectedBarcodeCount: result.detectedBarcodes.count,
        payloadKindsExact: result.detectedBarcodes.map(\.payloadKind).sorted(by: kindOrder)
          == expectedPayloadKinds.sorted(by: kindOrder),
        backFieldsExact: GoldenFieldComparison.mismatchedFields(
          expected: backExpected, result: result.fields
        ).isEmpty,
        mergedFieldsExact: GoldenFieldComparison.mismatchedFields(
          expected: mergedExpected, result: merged
        ).isEmpty,
        duplicateFree: Self.isDuplicateFree(merged),
        reviewDecisionExact: merged.warnings.contains(.reviewRecommended) == reviewExpected,
        cardRegionDecisionExact: cardRegionDecisionIsExact(
          result.cardRegionSelection,
          attemptsCardIsolation: attemptsCardIsolation
        ),
        durationMilliseconds: durationMilliseconds,
        tags: tags,
        diagnostics: result.diagnostics
      )
    }

    static func scanConfiguration(
      attemptsCardIsolation: Bool,
      maskingStrategy: AppleVisionBarcodeMaskingStrategy = .rectifiedRedetection,
      barcodeDetectionRecovery: AppleVisionBarcodeDetectionRecoveryOptions =
        AppleVisionBarcodeDetectionRecoveryOptions()
    ) -> AppleVisionScanConfiguration {
      AppleVisionScanConfiguration(
        recognitionLanguages: ["ko-KR", "en-US"],
        automaticallyDetectsLanguage: true,
        cardRegion: AppleVisionCardRegionConfiguration(
          mode: attemptsCardIsolation ? .automatic : .disabled
        ),
        preprocessing: AppleVisionPreprocessingConfiguration(isEnabled: false),
        dualPassRecognition: false,
        performsTargetedReRecognition: false,
        barcodeMaskingStrategy: maskingStrategy,
        barcodeDetectionRecovery: barcodeDetectionRecovery
      )
    }

    private static func cardRegionDecisionIsExact(
      _ selection: AppleVisionCardRegionSelection?,
      attemptsCardIsolation: Bool
    ) -> Bool {
      switch (attemptsCardIsolation, selection) {
      case (true, .isolated): true
      case (false, .disabled): true
      // QR-only scans legitimately omit a text result and therefore have no
      // card-region decision to expose.
      case (false, nil): true
      default: false
      }
    }

    static func result(from expected: [String: [String]]) -> CardFieldResult {
      func values(_ field: CardField) -> [ClassifiedValue] {
        (expected[field.rawValue] ?? []).map { text in
          ClassifiedValue(
            normalizedValue: text,
            originalValue: text,
            confidence: 0.99,
            evidence: [.syntaxMatch],
            sourceTokenIdentifiers: ["benchmark:front"]
          )
        }
      }
      return CardFieldResult(
        fullName: values(.fullName).first,
        alternateNames: values(.alternateNames),
        preferredName: values(.preferredName).first,
        jobTitle: values(.jobTitle).first,
        department: values(.department).first,
        organization: values(.organization).first,
        emailAddresses: values(.emailAddresses),
        mobilePhoneNumbers: values(.mobilePhoneNumbers),
        workPhoneNumbers: values(.workPhoneNumbers),
        faxNumbers: values(.faxNumbers),
        websites: values(.websites),
        professionalProfileURLs: values(.professionalProfileURLs),
        socialHandles: values(.socialHandles),
        addresses: values(.addresses)
      )
    }

    static func isDuplicateFree(_ result: CardFieldResult) -> Bool {
      let regular = [
        result.emailAddresses, result.websites, result.professionalProfileURLs,
        result.socialHandles, result.addresses,
      ].flatMap { $0 }.map { identity($0.normalizedValue) }
      let phones = (result.mobilePhoneNumbers + result.workPhoneNumbers + result.faxNumbers)
        .map { $0.normalizedValue.filter(\.isNumber) }
      return Set(regular).count == regular.count && Set(phones).count == phones.count
    }

    private static func identity(_ value: String) -> String {
      value.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      ).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func milliseconds(_ duration: Duration) -> Double {
      let components = duration.components
      return Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func kindOrder(
      _ lhs: AppleVisionDetectedBarcode.PayloadKind,
      _ rhs: AppleVisionDetectedBarcode.PayloadKind
    ) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }
#endif
