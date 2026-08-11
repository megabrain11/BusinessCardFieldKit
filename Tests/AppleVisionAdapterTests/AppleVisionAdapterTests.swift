import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import ImageIO
  import Vision

  @Test("Recognized lines map text, geometry, confidence, language, and stable identifiers")
  func recognizedLineMapping() throws {
    let lines = [
      RecognizedLine(
        text: "  Alex Kim  ",
        boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.31, height: 0.09),
        confidence: 0.94
      ),
      RecognizedLine(
        text: " \n ",
        boundingBox: CGRect(x: 0, y: 0, width: 0, height: 0),
        confidence: 0.10
      ),
      RecognizedLine(
        text: "alex@example.com",
        boundingBox: CGRect(x: 0.12, y: 0.20, width: 0.55, height: 0.06),
        confidence: 0.88
      ),
    ]

    let tokens = AppleVisionAdapter.tokens(from: lines, language: "en")

    #expect(tokens.count == 2)
    #expect(tokens.map(\.id) == ["vision-0001", "vision-0003"])
    #expect(tokens.map(\.text) == ["  Alex Kim  ", "alex@example.com"])
    #expect(tokens.allSatisfy { $0.language == "en" })
    #expect(tokens[0].boundingBox == .init(x: 0.10, y: 0.72, width: 0.31, height: 0.09))
    #expect(abs(tokens[0].confidence - 0.94) < 0.000_001)

    let scan = try AppleVisionScanner().makeResult(from: tokens)
    #expect(scan.tokens == tokens)
    #expect(scan.fields.fullName?.normalizedValue == "Alex Kim")
    #expect(scan.fields.emailAddresses.map(\.normalizedValue) == ["alex@example.com"])
  }

  @Test("Scan configuration is clamped and copied to the Vision request")
  func requestConfiguration() {
    let configuration = AppleVisionScanConfiguration(
      recognitionLevel: .fast,
      recognitionLanguages: ["ko-KR", "en-US"],
      automaticallyDetectsLanguage: false,
      usesLanguageCorrection: false,
      minimumTextHeight: 2,
      tokenLanguage: "ko"
    )
    let request = AppleVisionScanner.makeRequest(configuration: configuration)

    #expect(configuration.minimumTextHeight == 1)
    #expect(request.recognitionLevel == .fast)
    #expect(request.recognitionLanguages == ["ko-KR", "en-US"])
    #expect(request.automaticallyDetectsLanguage == false)
    #expect(request.usesLanguageCorrection == false)
    #expect(request.minimumTextHeight == 1)
  }

  @Test("EXIF orientation values map to the matching Core Graphics orientation")
  func imageOrientationMapping() {
    #expect(AppleVisionScanner.orientation(fromMetadataValue: 1) == .up)
    #expect(AppleVisionScanner.orientation(fromMetadataValue: 6) == .right)
    #expect(AppleVisionScanner.orientation(fromMetadataValue: 8) == .left)
    #expect(AppleVisionScanner.orientation(fromMetadataValue: nil) == .up)
    #expect(AppleVisionScanner.orientation(fromMetadataValue: 99) == .up)
  }

  @Test("Invalid encoded bytes fail before a Vision request is performed")
  func invalidImageData() {
    #expect(throws: AppleVisionScanError.invalidImageData) {
      try AppleVisionScanner().scan(imageData: Data("not an image".utf8))
    }
  }

  @Test("A blank decoded image reports that no text was recognized")
  func blankImage() throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try #require(
      CGContext(
        data: nil,
        width: 640,
        height: 400,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    )
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
    let image = try #require(context.makeImage())

    #expect(throws: AppleVisionScanError.noRecognizedText) {
      try AppleVisionScanner().scan(cgImage: image)
    }
  }
#else
  @Test("The adapter target remains resolvable without Apple Vision")
  func adapterTargetLoads() {
    _ = AppleVisionAdapter.self
  }
#endif
