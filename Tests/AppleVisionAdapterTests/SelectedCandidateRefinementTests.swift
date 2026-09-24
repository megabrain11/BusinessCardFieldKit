import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import CoreText

  @Test("Targeted re-recognition runs once, for the selected card candidate only")
  func targetedRefinementRunsOnlyForSelectedCandidate() throws {
    let scanner = AppleVisionScanner(
      configuration: AppleVisionScanConfiguration(
        recognitionLanguages: ["en-US"],
        automaticallyDetectsLanguage: false,
        dualPassRecognition: false,
        targetedReRecognitionConfidenceLimit: 1,
        diagnostics: AppleVisionDiagnosticsOptions(isEnabled: true)
      )
    )

    let scan = try scanner.scan(cgImage: try renderedTwoCardScene())
    let diagnostics = try #require(scan.diagnostics)

    guard case .isolated = scan.cardRegionSelection else {
      Issue.record("Automatic isolation should select one of the two cards.")
      return
    }
    let emails = scan.fields.emailAddresses.map(\.normalizedValue)
    #expect(emails == ["casey.morgan@example.com"] || emails == ["taylor.brooks@example.org"])

    // Two candidate OCR requests plus one targeted request show that both cards were
    // evaluated while refinement ran only for the winner.
    #expect(diagnostics.primaryTextRecognitionRequestCount >= 3)
    #expect(diagnostics.targetedReRecognitionRequestCount == 1)
  }

  private func renderedTwoCardScene() throws -> CGImage {
    let size = CGSize(width: 2_400, height: 1_200)
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
    context.setFillColor(CGColor(gray: 0.15, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))

    let cards: [(origin: CGPoint, lines: [(String, CGFloat)])] = [
      (
        CGPoint(x: 120, y: 300),
        [
          ("Casey Morgan", 60), ("Product Director", 40),
          ("casey.morgan@example.com", 34), ("Tel +1 202 555 0181", 34),
        ]
      ),
      (
        CGPoint(x: 1_260, y: 300),
        [
          ("Taylor Brooks", 60), ("Principal Engineer", 40),
          ("taylor.brooks@example.org", 34), ("Tel +1 415 555 0126", 34),
        ]
      ),
    ]
    for card in cards {
      context.setFillColor(CGColor(gray: 0.96, alpha: 1))
      context.fill(CGRect(origin: card.origin, size: CGSize(width: 1_020, height: 580)))
      var baseline = card.origin.y + 460
      for (text, fontSize) in card.lines {
        draw(text, at: CGPoint(x: card.origin.x + 70, y: baseline), fontSize: fontSize, in: context)
        baseline -= fontSize * 2.2
      }
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
#endif
