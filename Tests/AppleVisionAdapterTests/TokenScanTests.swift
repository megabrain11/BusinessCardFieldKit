import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import CoreImage
  import CoreText

  private struct FailingCorrectionStore: CorrectionStore {
    struct LoadFailure: Error {}

    func loadCorrections() throws -> [PersonalCorrection] {
      throw LoadFailure()
    }
  }

  private func makeWorksheetConfiguration() -> AppleVisionScanConfiguration {
    AppleVisionScanConfiguration(
      recognitionLanguages: ["ko-KR", "en-US"],
      automaticallyDetectsLanguage: true,
      cardRegion: AppleVisionCardRegionConfiguration(mode: .disabled),
      preprocessing: AppleVisionPreprocessingConfiguration(),
      dualPassRecognition: true,
      performsTargetedReRecognition: true
    )
  }

  @Test("scanTokens honors document-style settings and returns invariant-satisfying tokens")
  func scanTokensInvariants() throws {
    let page = try renderedWorksheet()
    let scanner = AppleVisionScanner(configuration: makeWorksheetConfiguration())

    let result = try scanner.scanTokens(cgImage: page)

    #expect(result.cardRegionSelection == .disabled)
    #expect(!result.tokens.isEmpty)
    for token in result.tokens {
      #expect(!token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      #expect((0.0...1.0).contains(token.confidence))
      #expect(token.boundingBox.isValid)
      for alternative in token.alternatives {
        #expect(!alternative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(alternative != token.text)
      }
    }
  }

  @Test("Token identifiers follow the stable positional reading order")
  func stableIdentifiers() throws {
    let page = try renderedWorksheet()
    let scanner = AppleVisionScanner(configuration: makeWorksheetConfiguration())

    let result = try scanner.scanTokens(cgImage: page)

    let expectedIDs = (1...result.tokens.count).map { String(format: "vision-%04d", $0) }
    #expect(result.tokens.map(\.id) == expectedIDs)
    #expect(Set(result.tokens.map(\.id)).count == result.tokens.count)
  }

  @Test("Repeated runs and the asynchronous variant return identical token scans")
  func syncAsyncParityAndStability() async throws {
    let page = try renderedWorksheet()
    let scanner = AppleVisionScanner(configuration: makeWorksheetConfiguration())

    let direct = try scanner.scanTokens(cgImage: page)
    let again = try scanner.scanTokens(cgImage: page)
    let async = try await scanner.scanTokensAsync(cgImage: page)

    #expect(direct == again)
    #expect(direct == async)
  }

  @Test("Existing scan tokens equal scanTokens tokens and fields still classify")
  func scanParityAndFieldRegression() throws {
    let card = try renderedCardFront()
    let configuration = AppleVisionScanConfiguration(
      recognitionLanguages: ["en-US"],
      automaticallyDetectsLanguage: false,
      cardRegion: AppleVisionCardRegionConfiguration(mode: .disabled)
    )
    let scanner = AppleVisionScanner(configuration: configuration)

    let scan = try scanner.scan(cgImage: card)
    let tokenOnly = try scanner.scanTokens(cgImage: card)

    #expect(scan.tokens == tokenOnly.tokens)
    #expect(scan.cardRegionSelection == tokenOnly.cardRegionSelection)
    #expect(scan.fields.fullName?.normalizedValue == "Alex Kim")
    #expect(scan.fields.emailAddresses.map(\.normalizedValue) == ["alex.kim@example.com"])
    #expect(tokenOnly.tokens.contains { $0.language == "en" })
  }

  @Test("scanTokens succeeds while classification fails on the same input")
  func independentOfClassificationFailure() throws {
    let card = try renderedCardFront()
    let configuration = AppleVisionScanConfiguration(
      recognitionLanguages: ["en-US"],
      automaticallyDetectsLanguage: false,
      cardRegion: AppleVisionCardRegionConfiguration(mode: .disabled)
    )
    let failingScanner = AppleVisionScanner(
      classifier: CardFieldClassifier(correctionStore: FailingCorrectionStore()),
      configuration: configuration
    )

    do {
      _ = try failingScanner.scan(cgImage: card)
      Issue.record("expected classificationFailed from the field scan")
    } catch let error as AppleVisionScanError {
      guard case .classificationFailed = error else {
        Issue.record("unexpected scan error \(error)")
        return
      }
    } catch {
      Issue.record("unexpected error \(error)")
    }

    let tokenOnly = try failingScanner.scanTokens(cgImage: card)
    #expect(!tokenOnly.tokens.isEmpty)
    #expect(tokenOnly.cardRegionSelection == .disabled)
  }

  @Test("Automatic card-region isolation still applies to token-only scanning")
  func automaticRegionTokenScan() async throws {
    let scene = try renderedSceneWithSkewedCard()
    let scanner = AppleVisionScanner(
      configuration: AppleVisionScanConfiguration(recognitionLanguages: ["en-US"])
    )

    let result = try await scanner.scanTokensAsync(cgImage: scene)

    if case .isolated(let region) = result.cardRegionSelection {
      #expect(region.selectionScore > 0)
    } else if case .fullImageFallback = result.cardRegionSelection {
      // Conservative fallback is acceptable when rectangle evidence is weak.
    } else {
      Issue.record("unexpected disabled selection for automatic mode")
    }
    #expect(!result.tokens.isEmpty)
  }

  @Test("Token conversion preserves id, text, box, confidence, language, and alternatives")
  func tokenMetadataPreservation() {
    let line = RecognizedLine(
      text: "Question 1",
      boundingBox: CGRect(x: 0.08, y: 0.62, width: 0.42, height: 0.05),
      confidence: 0.82,
      alternatives: ["Questlon 1", "Question I"]
    )

    let tokens = AppleVisionAdapter.tokens(from: [line], language: nil, infersLanguages: true)

    #expect(tokens.count == 1)
    #expect(tokens[0].id == "vision-0001")
    #expect(tokens[0].text == "Question 1")
    #expect(tokens[0].boundingBox == .init(x: 0.08, y: 0.62, width: 0.42, height: 0.05))
    #expect(abs(tokens[0].confidence - 0.82) < 0.000_001)
    #expect(tokens[0].language == "en")
    #expect(tokens[0].alternatives == ["Questlon 1", "Question I"])
  }

  @Test("Legacy encoded tokens without alternatives still decode")
  func legacyAlternativesDecoding() throws {
    let json = """
      {"id":"vision-0001","text":"19","boundingBox":{"x":0.1,"y":0.2,"width":0.05,"height":0.02},"confidence":0.9}
      """
    let token = try JSONDecoder().decode(OCRToken.self, from: Data(json.utf8))
    #expect(token.alternatives.isEmpty)
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

    var y = size.height * 0.78
    for (text, fontSize) in lines {
      draw(text, at: CGPoint(x: size.width * 0.10, y: y), fontSize: fontSize, in: context)
      y -= fontSize * 2.2
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

  private func renderedWorksheet() throws -> CGImage {
    try renderedImage(
      lines: [
        ("Practice Worksheet", 56),
        ("연습 시트", 44),
        ("Question 1. 12 + 7 = ____", 36),
        ("Answer: 19", 36),
        ("Question 2. 9 x 6 = ____", 36),
        ("Score: ____ / 100", 32),
      ],
      size: CGSize(width: 1_600, height: 900)
    )
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
#else
  @Test("Token scan tests require Apple Vision")
  func tokenScanTestsUnavailable() {}
#endif
