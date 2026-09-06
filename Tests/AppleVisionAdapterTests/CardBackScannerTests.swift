import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import CoreImage
  import Vision

  @Test("Card-back QR vCard is decoded and merged without exposing its raw payload")
  func vCardQRCodeScan() throws {
    let payload = """
      BEGIN:VCARD
      VERSION:3.0
      FN:Alex Kim
      ORG:Example Labs
      TEL;TYPE=CELL:+1-202-555-0101
      EMAIL:alex.kim@example.com
      URL:https://example.com/alex
      END:VCARD
      """
    let image = try qrCode(payload)
    let scanner = CardBackScanner(
      configuration: AppleVisionScanConfiguration(
        recognitionLanguages: ["en-US"],
        automaticallyDetectsLanguage: false,
        cardRegion: AppleVisionCardRegionConfiguration(mode: .disabled),
        preprocessing: AppleVisionPreprocessingConfiguration(isEnabled: false),
        dualPassRecognition: false,
        performsTargetedReRecognition: false
      )
    )

    let result = try scanner.scan(cgImage: image)

    #expect(result.detectedBarcodes.count == 1)
    #expect(result.detectedBarcodes[0].payloadKind == .vCard)
    #expect(result.detectedBarcodes[0].boundingBox.isValid)
    #expect(result.fields.fullName?.normalizedValue == "Alex Kim")
    #expect(result.fields.organization?.normalizedValue == "Example Labs")
    #expect(result.fields.mobilePhoneNumbers.map(\.normalizedValue) == ["+1-202-555-0101"])
    #expect(result.fields.emailAddresses.map(\.normalizedValue) == ["alex.kim@example.com"])
    #expect(result.fields.websites.map(\.normalizedValue) == ["https://example.com/alex"])
    #expect(
      result.fields.emailAddresses[0].sourceTokenIdentifiers[0]
        .hasPrefix("barcode:0001:vcard:")
    )
  }

  @Test("Card-back URL QR becomes a website and unsupported payload remains unclassified")
  func urlAndUnsupportedQRCodeScan() throws {
    let configuration = AppleVisionScanConfiguration(
      recognitionLanguages: ["en-US"],
      automaticallyDetectsLanguage: false,
      cardRegion: AppleVisionCardRegionConfiguration(mode: .disabled),
      preprocessing: AppleVisionPreprocessingConfiguration(isEnabled: false),
      dualPassRecognition: false,
      performsTargetedReRecognition: false
    )
    let scanner = CardBackScanner(configuration: configuration)

    let url = try scanner.scan(cgImage: qrCode("https://example.org/profile"))
    #expect(url.detectedBarcodes.map(\.payloadKind) == [.url])
    #expect(url.fields.websites.map(\.normalizedValue) == ["https://example.org/profile"])

    let unsupported = try scanner.scan(cgImage: qrCode("fictional-reference-555-0199"))
    #expect(unsupported.detectedBarcodes.map(\.payloadKind) == [.unsupported])
    #expect(unsupported.fields.websites.isEmpty)
    #expect(unsupported.fields.emailAddresses.isEmpty)
  }

  private func qrCode(_ payload: String) throws -> CGImage {
    let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
    filter.setValue(Data(payload.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    let output = try #require(filter.outputImage)
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    return try #require(CIContext().createCGImage(scaled, from: scaled.extent))
  }
#endif
