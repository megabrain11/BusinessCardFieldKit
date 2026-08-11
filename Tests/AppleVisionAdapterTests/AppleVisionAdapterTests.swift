import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import CoreImage
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

  @Test("Card-region configuration clamps public limits and configures rectangle detection")
  func cardRegionRequestConfiguration() {
    let configuration = AppleVisionCardRegionConfiguration(
      maximumObservations: 0,
      maximumTextRecognitionCandidates: 99,
      minimumConfidence: -1,
      minimumSize: 2,
      minimumAreaRatio: -1,
      preferredAspectRatio: 0.5,
      aspectRatioTolerance: -2,
      quadratureTolerance: 90,
      minimumTextEvidenceScore: 2
    )
    let request = AppleVisionScanner.makeRectangleRequest(configuration: configuration)

    #expect(configuration.maximumObservations == 1)
    #expect(configuration.maximumTextRecognitionCandidates == 1)
    #expect(configuration.minimumConfidence == 0)
    #expect(configuration.minimumSize == 1)
    #expect(configuration.minimumAreaRatio == 0)
    #expect(configuration.preferredAspectRatio == 1)
    #expect(configuration.aspectRatioTolerance == 0)
    #expect(configuration.quadratureTolerance == 45)
    #expect(configuration.minimumTextEvidenceScore == 1)
    #expect(request.maximumObservations == 1)
    #expect(request.minimumConfidence == 0)
    #expect(request.minimumSize == 1)
    #expect(request.minimumAspectRatio == 1)
    #expect(request.maximumAspectRatio == 1)
    #expect(request.quadratureTolerance == 45)

    var mutated = AppleVisionCardRegionConfiguration()
    mutated.maximumObservations = -4
    mutated.maximumTextRecognitionCandidates = 40
    mutated.minimumConfidence = 8
    mutated.minimumTextEvidenceScore = -2
    let normalized = mutated.normalized
    #expect(normalized.maximumObservations == 1)
    #expect(normalized.maximumTextRecognitionCandidates == 1)
    #expect(normalized.minimumConfidence == 1)
    #expect(normalized.minimumTextEvidenceScore == 0)
  }

  @Test("Synthetic geometry ranks a central card and suppresses square and duplicate regions")
  func cardRegionGeometryRanking() throws {
    let configuration = AppleVisionCardRegionConfiguration(
      minimumConfidence: 0.4,
      minimumAreaRatio: 0.02
    )
    let foreground = candidate(x: 0.19, y: 0.14, width: 0.62, height: 0.35)
    let background = candidate(x: 0.02, y: 0.68, width: 0.42, height: 0.24)
    let keyboardKey = candidate(x: 0.40, y: 0.84, width: 0.10, height: 0.10)
    let foregroundDuplicate = candidate(
      x: 0.195,
      y: 0.145,
      width: 0.61,
      height: 0.34,
      confidence: 0.80
    )

    let ranked = CardRegionSelector.rankedCandidates(
      [background, keyboardKey, foregroundDuplicate, foreground],
      configuration: configuration,
      limit: 4
    )

    #expect(ranked.count == 2)
    #expect(try #require(ranked.first) == foreground)
    #expect(ranked.contains(background))
    #expect(!ranked.contains(keyboardKey))
    #expect(!ranked.contains(foregroundDuplicate))
  }

  @Test("Contact-text cohesion outweighs a plausible background rectangle")
  func cardTextEvidenceRanking() {
    let minimumEvidence = AppleVisionCardRegionConfiguration().minimumTextEvidenceScore
    let foregroundEvidence = CardTextEvidence.score([
      "Alex Morgan",
      "Founder & CEO",
      "+1 202 555 0147",
      "www.example.com",
      "alex@example.com",
      "Address: 123 Example Road, Example City",
    ])
    let backgroundEvidence = CardTextEvidence.score(["Lifetime Value Creator"])

    let foregroundScore = CardRegionSelector.selectionScore(
      geometryScore: 0.60,
      textEvidenceScore: foregroundEvidence
    )
    let backgroundScore = CardRegionSelector.selectionScore(
      geometryScore: 0.90,
      textEvidenceScore: backgroundEvidence
    )

    #expect(foregroundEvidence > 0.80)
    #expect(foregroundEvidence >= minimumEvidence)
    #expect(backgroundEvidence < minimumEvidence)
    #expect(foregroundScore > backgroundScore)
  }

  @Test("Perspective correction crops a programmatically rendered card quadrilateral")
  func syntheticPerspectiveCorrection() throws {
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
    let sourceImage = try #require(context.makeImage())
    let region = CardRegionCandidate(
      topLeft: CGPoint(x: 0.20, y: 0.75),
      topRight: CGPoint(x: 0.80, y: 0.70),
      bottomLeft: CGPoint(x: 0.25, y: 0.25),
      bottomRight: CGPoint(x: 0.75, y: 0.20),
      confidence: 1
    )

    let corrected = try #require(
      AppleVisionScanner.perspectiveCorrectedImage(
        CIImage(cgImage: sourceImage),
        candidate: region,
        context: CIContext()
      )
    )

    #expect(corrected.width < sourceImage.width)
    #expect(corrected.height < sourceImage.height)
    #expect(corrected.width > corrected.height)
    #expect((1.3...2.2).contains(Double(corrected.width) / Double(corrected.height)))
  }

  @Test("Vision boxes slightly outside the unit square are clamped before classification")
  func recognizedLineBoxClamping() {
    let tokens = AppleVisionAdapter.tokens(from: [
      RecognizedLine(
        text: "Alex Kim",
        boundingBox: CGRect(x: -0.02, y: 0.98, width: 0.10, height: 0.10),
        confidence: 0.9
      ),
      RecognizedLine(
        text: "Invalid geometry",
        boundingBox: CGRect(x: .infinity, y: 0, width: 0.2, height: 0.1),
        confidence: 0.9
      ),
    ])

    #expect(tokens.count == 1)
    #expect(tokens[0].boundingBox.isValid)
    #expect(abs(tokens[0].boundingBox.x - 0) < 0.000_001)
    #expect(abs(tokens[0].boundingBox.y - 0.98) < 0.000_001)
    #expect(abs(tokens[0].boundingBox.width - 0.08) < 0.000_001)
    #expect(abs(tokens[0].boundingBox.height - 0.02) < 0.000_001)
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

  private func candidate(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    confidence: Float = 0.95
  ) -> CardRegionCandidate {
    CardRegionCandidate(
      topLeft: CGPoint(x: x, y: y + height),
      topRight: CGPoint(x: x + width, y: y + height),
      bottomLeft: CGPoint(x: x, y: y),
      bottomRight: CGPoint(x: x + width, y: y),
      confidence: confidence
    )
  }
#else
  @Test("The adapter target remains resolvable without Apple Vision")
  func adapterTargetLoads() {
    _ = AppleVisionAdapter.self
  }
#endif
