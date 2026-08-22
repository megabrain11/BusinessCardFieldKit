import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import CoreImage
  import CoreText
  import ImageIO
  import Vision

  // MARK: - Dual-pass merging

  @Test("Strict-syntax lines keep the uncorrected reading; prose keeps correction")
  func dualPassMerging() {
    let corrected = [
      RecognizedLine(
        text: "Alex K1m", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.06),
        confidence: 0.9),
      RecognizedLine(
        text: "alex.kim@exampl3.net", boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.05),
        confidence: 0.85),
    ]
    let uncorrected = [
      RecognizedLine(
        text: "Alex Kim", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.06),
        confidence: 0.7),
      RecognizedLine(
        text: "alex.kim@example.net", boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.05),
        confidence: 0.8),
    ]

    let merged = AppleVisionScanner.mergedLines(corrected: corrected, uncorrected: uncorrected)

    #expect(merged.count == 2)
    // Prose keeps the language-corrected reading; strict syntax keeps raw text.
    #expect(merged[0].text == "Alex K1m")
    #expect(abs(merged[0].confidence - 0.9) < 0.000_001)
    #expect(merged[1].text == "alex.kim@example.net")
    #expect(merged[0].alternatives.contains("Alex Kim"))
    #expect(merged[1].alternatives.contains("alex.kim@exampl3.net"))
  }

  @Test("Unpaired lines from both passes survive merging in stable order")
  func dualPassUnpairedLines() {
    let corrected = [
      RecognizedLine(
        text: "Founder & CEO", boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.05),
        confidence: 0.9)
    ]
    let uncorrected = [
      RecognizedLine(
        text: "www.example.com", boundingBox: CGRect(x: 0.4, y: 0.2, width: 0.3, height: 0.04),
        confidence: 0.8)
    ]

    let merged = AppleVisionScanner.mergedLines(corrected: corrected, uncorrected: uncorrected)
    #expect(merged.map(\.text) == ["Founder & CEO", "www.example.com"])
  }

  @Test("Emails, phones, and URLs prefer uncorrected readings")
  func strictSyntaxDetection() {
    #expect(AppleVisionScanner.prefersUncorrectedText("alex@example.com"))
    #expect(AppleVisionScanner.prefersUncorrectedText("+82 2 555 0123"))
    #expect(AppleVisionScanner.prefersUncorrectedText("www.example.com/ko"))
    #expect(AppleVisionScanner.prefersUncorrectedText("https://example.com/about"))
    #expect(AppleVisionScanner.prefersUncorrectedText("example.co.kr"))
    #expect(!AppleVisionScanner.prefersUncorrectedText("Chief Executive Officer"))
    #expect(!AppleVisionScanner.prefersUncorrectedText("김민서 대표이사"))
    #expect(!AppleVisionScanner.prefersUncorrectedText(""))
  }

  @Test("Multi-candidate readings populate token alternatives without duplicates")
  func candidateCollection() {
    let line = RecognizedLine(
      text: "alex@examp1e.net",
      boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.05),
      confidence: 0.8,
      alternatives: ["alex@examp1e.net", "alex@example.net", "alex@example.org"]
    )

    let tokens = AppleVisionAdapter.tokens(from: [line], language: "en")

    #expect(tokens.count == 1)
    #expect(tokens[0].text == "alex@examp1e.net")
    #expect(tokens[0].alternatives == ["alex@example.net", "alex@example.org"])
    #expect(tokens[0].language == "en")

    let inferred = AppleVisionAdapter.tokens(
      from: [line], language: nil, infersLanguages: true
    )
    #expect(inferred[0].language == "en")
  }

  // MARK: - Targeted re-recognition geometry

  @Test("Crop rects convert between pixel and normalized spaces consistently")
  func cropGeometryRoundTrip() {
    let imageSize = CGSize(width: 2_000, height: 1_000)
    let unionBox = NormalizedBoundingBox(x: 0.10, y: 0.30, width: 0.50, height: 0.20)

    guard
      let cropRect = AppleVisionScanner.pixelCropRect(
        for: unionBox,
        imageSize: imageSize,
        padding: 0.02
      )
    else {
      Issue.record("crop rect should be produced")
      return
    }
    #expect(cropRect.minY == 480)
    #expect(cropRect.maxX == 1_240)

    let frame = AppleVisionScanner.normalizedFrame(of: cropRect, in: imageSize)
    #expect(abs(frame.minX - 0.08) < 0.000_001)
    #expect(abs(frame.maxY - 0.52) < 0.000_001)

    let lineInCrop = CGRect(x: 0.5, y: 0.25, width: 0.3, height: 0.1)
    let absolute = AppleVisionScanner.absoluteBox(lineInCrop, within: frame)
    #expect(absolute.midX > frame.minX && absolute.midX < frame.maxX)
    #expect(AppleVisionScanner.centersOverlap(absolute, absolute))
  }

  @Test("Boxes inflate inside the unit square without negative sizes")
  func inflationClamping() {
    let edge = NormalizedBoundingBox(x: 0.98, y: 0.01, width: 0.02, height: 0.02)
    let inflated = AppleVisionScanner.inflated(edge, fraction: 0.5)
    #expect(inflated.isValid)
    #expect(inflated.x + inflated.width <= 1.000_001)

    let center = NormalizedBoundingBox(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
    let widened = AppleVisionScanner.inflated(center, fraction: 0.5)
    #expect(abs(widened.width - 0.4) < 0.000_001)
  }

  @Test("Low-confidence tokens below the limit are selected for refinement")
  func refinementSelection() throws {
    let tokens = [
      OCRToken(
        id: "a", text: "blurry line",
        boundingBox: .init(x: 0.1, y: 0.4, width: 0.4, height: 0.04), confidence: 0.20),
      OCRToken(
        id: "b", text: "sharp line",
        boundingBox: .init(x: 0.1, y: 0.3, width: 0.4, height: 0.04), confidence: 0.90),
    ]
    let configuration = AppleVisionScanConfiguration()
    let working = try renderedImage(
      lines: [("anything", 40)], size: CGSize(width: 400, height: 200))
    let refined = AppleVisionScanner(configuration: configuration)
      .refinedForTesting(tokens, in: working)
    #expect(refined.count == 2)
    #expect(refined[0].id == "a")
    #expect(refined[1].text == "sharp line")
  }

  // MARK: - Preprocessing

  @Test("Preprocessing upscales small images to the configured long edge")
  func preprocessingUpscaling() throws {
    let small = try renderedImage(lines: [("Hello", 24)], size: CGSize(width: 320, height: 180))
    var configuration = AppleVisionPreprocessingConfiguration()
    configuration.minimumLongEdge = 1_600

    let enhanced = try #require(ImagePreprocessor.preprocess(small, configuration: configuration))
    #expect(max(enhanced.width, enhanced.height) >= 1_600)

    let untouched = ImagePreprocessor.preprocess(
      small, configuration: AppleVisionPreprocessingConfiguration(isEnabled: false)
    )
    #expect(untouched.width == small.width)
    #expect(untouched.height == small.height)
  }

  @Test("Standalone upscale respects the target edge and leaves larger images alone")
  func standaloneUpscale() throws {
    let image = try renderedImage(lines: [("Hi", 20)], size: CGSize(width: 300, height: 150))
    let scaled = try #require(ImagePreprocessor.upscale(image, targetLongEdge: 900))
    #expect(max(scaled.width, scaled.height) >= 900)
    #expect(ImagePreprocessor.upscale(scaled, targetLongEdge: 100) == nil)
  }

  // MARK: - Card detection enhancements

  @Test("Perspective correction can enforce a minimum output resolution")
  func perspectiveCorrectionScaling() throws {
    let source = try renderedQuadCard()
    let candidate = CardRegionCandidate(
      topLeft: CGPoint(x: 0.20, y: 0.75),
      topRight: CGPoint(x: 0.80, y: 0.70),
      bottomLeft: CGPoint(x: 0.25, y: 0.25),
      bottomRight: CGPoint(x: 0.75, y: 0.20),
      confidence: 1
    )
    let context = CIContext()

    let unscaled = try #require(
      AppleVisionScanner.perspectiveCorrectedImage(
        CIImage(cgImage: source), candidate: candidate, context: context
      )
    )
    let scaled = try #require(
      AppleVisionScanner.perspectiveCorrectedImage(
        CIImage(cgImage: source), candidate: candidate, context: context, minimumLongEdge: 1_500
      )
    )

    #expect(max(scaled.width, scaled.height) >= 1_500)
    #expect(max(unscaled.width, unscaled.height) < max(scaled.width, scaled.height))
  }

  @Test("Saliency fallback proposes card-shaped candidates clamped to the unit square")
  func saliencyCandidateGeometry() throws {
    let configuration = AppleVisionCardRegionConfiguration()

    let centered = try #require(
      CardRegionSelector.saliencyCandidate(
        fromSalientBox: CGRect(x: 0.42, y: 0.45, width: 0.16, height: 0.10),
        confidence: 1,
        configuration: configuration
      )
    )
    let box = centered.normalizedBoundingBox
    #expect(box.isValid)
    #expect(box.width > box.height)
    #expect(Double(centered.confidence) <= 0.75)

    let offCenter = try #require(
      CardRegionSelector.saliencyCandidate(
        fromSalientBox: CGRect(x: -0.4, y: 0.9, width: 0.5, height: 0.4),
        confidence: 1,
        configuration: configuration
      )
    )
    #expect(offCenter.normalizedBoundingBox.isValid)

    let degenerate = CardRegionSelector.saliencyCandidate(
      fromSalientBox: .zero, configuration: configuration
    )
    #expect(degenerate == nil)
  }

  // MARK: - End-to-end synthetic cards

  @Test("A fully rendered card front classifies through the complete scan pipeline")
  func endToEndSyntheticCard() async throws {
    let card = try renderedCardFront()
    let scanner = AppleVisionScanner(
      configuration: AppleVisionScanConfiguration(
        recognitionLanguages: ["en-US"],
        automaticallyDetectsLanguage: false,
        cardRegion: AppleVisionCardRegionConfiguration(mode: .disabled)
      )
    )

    let scan = try await scanner.scanAsync(cgImage: card)

    #expect(scan.fields.fullName?.normalizedValue == "Alex Kim")
    #expect(scan.fields.emailAddresses.map(\.normalizedValue) == ["alex.kim@example.com"])
    #expect(scan.cardRegionSelection == .disabled)

    let phoneDigits = (scan.fields.workPhoneNumbers + scan.fields.mobilePhoneNumbers)
      .map(\.normalizedValue)
    #expect(phoneDigits.contains { $0.contains("2025550147") })
    #expect(
      scan.fields.websites.contains {
        $0.normalizedValue.contains("example.com")
      })

    let nameToken = try #require(
      scan.tokens.first { $0.text.trimmingCharacters(in: .whitespaces) == "Alex Kim" }
    )
    #expect(nameToken.language == "en")
  }

  @Test("Isolated or fallback paths both recover a skewed foreground card")
  func endToEndSkewedCard() async throws {
    let scene = try renderedSceneWithSkewedCard()
    let scanner = AppleVisionScanner(
      configuration: AppleVisionScanConfiguration(recognitionLanguages: ["en-US"])
    )

    let scan = try await scanner.scanAsync(cgImage: scene)

    #expect(scan.fields.emailAddresses.map(\.normalizedValue) == ["jordan.lee@example.com"])
    if case .isolated(let region) = scan.cardRegionSelection {
      #expect(region.selectionScore > 0)
    } else if case .fullImageFallback = scan.cardRegionSelection {
      // Conservative fallback is acceptable when rectangle evidence is weak.
    } else {
      Issue.record("unexpected disabled selection for automatic mode")
    }
  }

  // MARK: - Rendering helpers

  private func renderedImage(
    lines: [(String, CGFloat)],
    size: CGSize,
    background: CGColor = CGColor(gray: 1, alpha: 1)
  ) throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    context.setFillColor(background)
    context.fill(CGRect(origin: .zero, size: size))

    var y = size.height * 0.72
    for (text, fontSize) in lines {
      draw(text, at: CGPoint(x: size.width * 0.08, y: y), fontSize: fontSize, in: context)
      y -= fontSize * 1.9
    }
    return try #require(context.makeImage())
  }

  private func draw(_ text: String, at point: CGPoint, fontSize: CGFloat, in context: CGContext) {
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let attributes: [CFString: Any] = [
      kCTFontAttributeName: font,
      kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
    ]
    guard
      let attributed = CFAttributedStringCreate(
        nil, text as CFString, attributes as CFDictionary
      )
    else { return }
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = point
    CTLineDraw(line, context)
  }

  private func renderedCardFront() throws -> CGImage {
    try renderedImage(
      lines: [
        ("Alex Kim", 64),
        ("Founder & CEO", 44),
        ("alex.kim@example.com", 36),
        ("Tel +1 202 555 0147", 36),
        ("www.example.com", 36),
      ],
      size: CGSize(width: 1_600, height: 900)
    )
  }

  private func renderedSceneWithSkewedCard() throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil,
        width: 2_000,
        height: 1_200,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    context.setFillColor(CGColor(gray: 0.15, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 2_000, height: 1_200))
    context.beginPath()
    context.move(to: CGPoint(x: 380, y: 950))
    context.addLine(to: CGPoint(x: 1_620, y: 915))
    context.addLine(to: CGPoint(x: 1_555, y: 330))
    context.addLine(to: CGPoint(x: 420, y: 365))
    context.closePath()
    context.setFillColor(CGColor(gray: 0.96, alpha: 1))
    context.fillPath()

    draw("Jordan Lee", at: CGPoint(x: 520, y: 800), fontSize: 58, in: context)
    draw("Product Director", at: CGPoint(x: 520, y: 700), fontSize: 40, in: context)
    draw("jordan.lee@example.com", at: CGPoint(x: 520, y: 560), fontSize: 34, in: context)
    draw("Tel +1 415 555 0198", at: CGPoint(x: 520, y: 470), fontSize: 34, in: context)
    return try #require(context.makeImage())
  }

  private func renderedQuadCard() throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil,
        width: 1_000,
        height: 700,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    context.setFillColor(CGColor(gray: 0.15, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 700))
    context.beginPath()
    context.move(to: CGPoint(x: 200, y: 525))
    context.addLine(to: CGPoint(x: 800, y: 490))
    context.addLine(to: CGPoint(x: 750, y: 140))
    context.addLine(to: CGPoint(x: 250, y: 175))
    context.closePath()
    context.setFillColor(CGColor(gray: 0.95, alpha: 1))
    context.fillPath()
    return try #require(context.makeImage())
  }
#else
  @Test("Adapter upgrade tests require Apple Vision")
  func adapterUpgradeTestsUnavailable() {}
#endif
