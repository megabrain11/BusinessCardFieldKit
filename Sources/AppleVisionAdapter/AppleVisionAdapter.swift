import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import CoreImage
  import ImageIO
  import Vision

  /// Configuration for isolating one foreground business card before text recognition.
  public struct AppleVisionCardRegionConfiguration: Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
      /// Detect plausible card rectangles, perspective-correct a bounded set, and select the
      /// candidate with the strongest geometric and contact-text evidence.
      case automatic

      /// Run text recognition against the complete source image.
      case disabled
    }

    /// Whether foreground-card isolation runs before text recognition.
    public var mode: Mode

    /// Maximum rectangles requested from Vision, clamped to at least one.
    public var maximumObservations: Int

    /// Maximum geometry-ranked rectangles that receive OCR, clamped to
    /// `1...maximumObservations`.
    public var maximumTextRecognitionCandidates: Int

    /// Minimum rectangle confidence accepted from Vision, clamped to `0...1`.
    public var minimumConfidence: Float

    /// Minimum candidate width or height relative to the upright source image, clamped to
    /// `0...1`.
    public var minimumSize: Float

    /// Minimum quadrilateral area relative to the upright source image, clamped to `0...1`.
    public var minimumAreaRatio: Double

    /// Preferred long-side-to-short-side ratio. Common business cards are close to `1.75`.
    public var preferredAspectRatio: Double

    /// Accepted absolute deviation from `preferredAspectRatio`.
    public var aspectRatioTolerance: Double

    /// Maximum corner-angle deviation supplied to Vision, clamped to `0...45` degrees.
    public var quadratureTolerance: Float

    /// Minimum contact-text cohesion required before a detected rectangle may replace full-image
    /// OCR, clamped to `0...1`.
    public var minimumTextEvidenceScore: Double

    public init(
      mode: Mode = .automatic,
      maximumObservations: Int = 8,
      maximumTextRecognitionCandidates: Int = 4,
      minimumConfidence: Float = 0.50,
      minimumSize: Float = 0.12,
      minimumAreaRatio: Double = 0.03,
      preferredAspectRatio: Double = 1.75,
      aspectRatioTolerance: Double = 0.65,
      quadratureTolerance: Float = 30,
      minimumTextEvidenceScore: Double = 0.45
    ) {
      let observationLimit = max(maximumObservations, 1)
      self.mode = mode
      self.maximumObservations = observationLimit
      self.maximumTextRecognitionCandidates = min(
        max(maximumTextRecognitionCandidates, 1),
        observationLimit
      )
      self.minimumConfidence = min(max(minimumConfidence, 0), 1)
      self.minimumSize = min(max(minimumSize, 0), 1)
      self.minimumAreaRatio = min(max(minimumAreaRatio, 0), 1)
      self.preferredAspectRatio = max(preferredAspectRatio, 1)
      self.aspectRatioTolerance = max(aspectRatioTolerance, 0)
      self.quadratureTolerance = min(max(quadratureTolerance, 0), 45)
      self.minimumTextEvidenceScore = min(max(minimumTextEvidenceScore, 0), 1)
    }

    var normalized: AppleVisionCardRegionConfiguration {
      AppleVisionCardRegionConfiguration(
        mode: mode,
        maximumObservations: maximumObservations,
        maximumTextRecognitionCandidates: maximumTextRecognitionCandidates,
        minimumConfidence: minimumConfidence,
        minimumSize: minimumSize,
        minimumAreaRatio: minimumAreaRatio,
        preferredAspectRatio: preferredAspectRatio,
        aspectRatioTolerance: aspectRatioTolerance,
        quadratureTolerance: quadratureTolerance,
        minimumTextEvidenceScore: minimumTextEvidenceScore
      )
    }
  }

  /// Configuration for local text recognition of an image containing a business-card front.
  public struct AppleVisionScanConfiguration: Equatable, Sendable {
    public enum RecognitionLevel: String, Codable, Sendable {
      case accurate
      case fast
    }

    /// The Vision recognition mode. Accurate recognition is the default for small card text.
    public var recognitionLevel: RecognitionLevel

    /// Ordered BCP 47 language hints supplied to Vision. An empty array lets Vision choose defaults.
    public var recognitionLanguages: [String]

    /// Whether Vision should identify the language of each text region automatically.
    public var automaticallyDetectsLanguage: Bool

    /// Whether Vision may use language-aware correction while recognizing text.
    public var usesLanguageCorrection: Bool

    /// The minimum text height relative to the image height, clamped to `0...1`.
    public var minimumTextHeight: Float

    /// An optional BCP 47 tag copied to every emitted token as a host-provided hint.
    /// Vision does not expose a detected language for individual recognized candidates.
    public var tokenLanguage: String?

    /// Foreground-card isolation applied before text recognition.
    public var cardRegion: AppleVisionCardRegionConfiguration

    public init(
      recognitionLevel: RecognitionLevel = .accurate,
      recognitionLanguages: [String] = [],
      automaticallyDetectsLanguage: Bool = true,
      usesLanguageCorrection: Bool = true,
      minimumTextHeight: Float = 0,
      tokenLanguage: String? = nil,
      cardRegion: AppleVisionCardRegionConfiguration = AppleVisionCardRegionConfiguration()
    ) {
      self.recognitionLevel = recognitionLevel
      self.recognitionLanguages = recognitionLanguages
      self.automaticallyDetectsLanguage = automaticallyDetectsLanguage
      self.usesLanguageCorrection = usesLanguageCorrection
      self.minimumTextHeight = min(max(minimumTextHeight, 0), 1)
      self.tokenLanguage = tokenLanguage
      self.cardRegion = cardRegion
    }
  }

  /// The selected card region in normalized, upright source-image coordinates.
  public struct AppleVisionDetectedCardRegion: Equatable, Sendable {
    public var boundingBox: NormalizedBoundingBox
    public var confidence: Double
    public var selectionScore: Double

    public init(
      boundingBox: NormalizedBoundingBox,
      confidence: Double,
      selectionScore: Double
    ) {
      self.boundingBox = boundingBox
      self.confidence = min(max(confidence, 0), 1)
      self.selectionScore = min(max(selectionScore, 0), 1)
    }
  }

  /// Explains whether OCR used an isolated card or the complete source image.
  public enum AppleVisionCardRegionSelection: Equatable, Sendable {
    /// Region isolation was explicitly disabled by configuration.
    case disabled

    /// A detected quadrilateral was perspective-corrected before OCR.
    case isolated(AppleVisionDetectedCardRegion)

    /// Automatic detection found no usable text-bearing card, so OCR used the full image.
    case fullImageFallback
  }

  /// The provider-neutral OCR tokens and structured suggestions produced from one card front.
  public struct AppleVisionScanResult: Equatable, Sendable {
    public var tokens: [OCRToken]
    public var fields: CardFieldResult
    public var cardRegionSelection: AppleVisionCardRegionSelection

    public init(
      tokens: [OCRToken],
      fields: CardFieldResult,
      cardRegionSelection: AppleVisionCardRegionSelection = .disabled
    ) {
      self.tokens = tokens
      self.fields = fields
      self.cardRegionSelection = cardRegionSelection
    }
  }

  /// Stable failure categories for the image-to-fields scan pipeline.
  public enum AppleVisionScanError: Error, Equatable, Sendable {
    /// The supplied bytes do not contain a decodable image.
    case invalidImageData

    /// Vision completed successfully but found no non-whitespace text.
    case noRecognizedText

    /// Vision could not analyze the image.
    case recognitionFailed(String)

    /// The injected field classifier could not load its rules or corrections.
    case classificationFailed(String)
  }

  extension AppleVisionScanError: LocalizedError {
    public var errorDescription: String? {
      switch self {
      case .invalidImageData:
        "The supplied data is not a decodable image."
      case .noRecognizedText:
        "No text was recognized on the card front."
      case .recognitionFailed(let message):
        "Apple Vision text recognition failed: \(message)"
      case .classificationFailed(let message):
        "Card-field classification failed: \(message)"
      }
    }
  }

  /// Runs Apple Vision locally and classifies the recognized front-side text.
  ///
  /// `scan` is synchronous. Hosts should call it away from latency-sensitive UI work.
  /// The scanner does not retain the image, persist results, or perform network requests.
  public struct AppleVisionScanner: Sendable {
    public var configuration: AppleVisionScanConfiguration

    private let classifier: CardFieldClassifier

    public init(
      classifier: CardFieldClassifier = CardFieldClassifier(),
      configuration: AppleVisionScanConfiguration = AppleVisionScanConfiguration()
    ) {
      self.classifier = classifier
      self.configuration = configuration
    }

    /// Scans encoded image bytes. When `orientation` is nil, EXIF orientation is used when present.
    public func scan(
      imageData: Data,
      orientation: CGImagePropertyOrientation? = nil
    ) throws -> AppleVisionScanResult {
      guard
        let source = CGImageSourceCreateWithData(imageData as CFData, nil),
        CGImageSourceGetCount(source) > 0,
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        throw AppleVisionScanError.invalidImageData
      }

      let resolvedOrientation = orientation ?? Self.orientation(from: source)
      return try scanImage(image, orientation: resolvedOrientation)
    }

    /// Scans a decoded image. `orientation` describes how its pixels must rotate to become upright.
    public func scan(
      cgImage: CGImage,
      orientation: CGImagePropertyOrientation = .up
    ) throws -> AppleVisionScanResult {
      try scanImage(cgImage, orientation: orientation)
    }

    private func scanImage(
      _ image: CGImage,
      orientation: CGImagePropertyOrientation
    ) throws -> AppleVisionScanResult {
      if configuration.cardRegion.mode == .automatic,
        let isolatedResult = isolatedCardResult(from: image, orientation: orientation)
      {
        return try makeResult(
          from: isolatedResult.tokens,
          cardRegionSelection: .isolated(isolatedResult.region)
        )
      }

      let tokens = try recognizeTokens(in: image, orientation: orientation)
      let selection: AppleVisionCardRegionSelection =
        configuration.cardRegion.mode == .disabled ? .disabled : .fullImageFallback
      return try makeResult(from: tokens, cardRegionSelection: selection)
    }

    private func recognizeLines(
      in image: CGImage,
      orientation: CGImagePropertyOrientation
    ) throws -> [RecognizedLine] {
      let request = Self.makeRequest(configuration: configuration)
      let handler = VNImageRequestHandler(
        cgImage: image,
        orientation: orientation,
        options: [:]
      )
      do {
        try handler.perform([request])
      } catch {
        throw AppleVisionScanError.recognitionFailed(error.localizedDescription)
      }

      return AppleVisionAdapter.recognizedLines(from: request.results ?? [])
    }

    private func recognizeTokens(
      in image: CGImage,
      orientation: CGImagePropertyOrientation
    ) throws -> [OCRToken] {
      AppleVisionAdapter.tokens(
        from: try recognizeLines(in: image, orientation: orientation),
        language: configuration.tokenLanguage
      )
    }

    private func isolatedCardResult(
      from image: CGImage,
      orientation: CGImagePropertyOrientation
    ) -> IsolatedCardRecognition? {
      let orientedImage = CIImage(cgImage: image).oriented(
        forExifOrientation: Int32(orientation.rawValue)
      )
      let regionConfiguration = configuration.cardRegion.normalized
      let request = Self.makeRectangleRequest(configuration: regionConfiguration)
      let handler = VNImageRequestHandler(ciImage: orientedImage, orientation: .up, options: [:])
      do {
        try handler.perform([request])
      } catch {
        return nil
      }

      let candidates = CardRegionSelector.rankedCandidates(
        (request.results ?? []).map {
          CardRegionCandidate($0, sourceSize: orientedImage.extent.size)
        },
        configuration: regionConfiguration,
        limit: regionConfiguration.maximumTextRecognitionCandidates
      )
      guard !candidates.isEmpty else { return nil }

      let context = CIContext()
      var best: IsolatedCardRecognition?
      for candidate in candidates {
        guard
          let correctedImage = Self.perspectiveCorrectedImage(
            orientedImage,
            candidate: candidate,
            context: context
          ),
          let lines = try? recognizeLines(in: correctedImage, orientation: .up),
          !lines.isEmpty
        else {
          continue
        }

        let textEvidenceScore = CardTextEvidence.score(lines.map(\.text))
        guard textEvidenceScore >= regionConfiguration.minimumTextEvidenceScore else {
          continue
        }
        let selectionScore = CardRegionSelector.selectionScore(
          geometryScore: candidate.geometryScore(configuration: regionConfiguration),
          textEvidenceScore: textEvidenceScore
        )
        let tokens = AppleVisionAdapter.tokens(
          from: lines,
          language: configuration.tokenLanguage
        )
        guard !tokens.isEmpty else { continue }

        let recognition = IsolatedCardRecognition(
          tokens: tokens,
          region: AppleVisionDetectedCardRegion(
            boundingBox: candidate.normalizedBoundingBox,
            confidence: Double(candidate.confidence),
            selectionScore: selectionScore
          ),
          selectionScore: selectionScore
        )
        if best == nil || selectionScore > best!.selectionScore {
          best = recognition
        }
      }
      return best
    }

    func makeResult(
      from tokens: [OCRToken],
      cardRegionSelection: AppleVisionCardRegionSelection = .disabled
    ) throws -> AppleVisionScanResult {
      guard !tokens.isEmpty else {
        throw AppleVisionScanError.noRecognizedText
      }

      do {
        return AppleVisionScanResult(
          tokens: tokens,
          fields: try classifier.classify(tokens),
          cardRegionSelection: cardRegionSelection
        )
      } catch {
        throw AppleVisionScanError.classificationFailed(error.localizedDescription)
      }
    }

    static func makeRequest(configuration: AppleVisionScanConfiguration) -> VNRecognizeTextRequest {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel =
        configuration.recognitionLevel == .accurate ? .accurate : .fast
      request.recognitionLanguages = configuration.recognitionLanguages
      request.automaticallyDetectsLanguage = configuration.automaticallyDetectsLanguage
      request.usesLanguageCorrection = configuration.usesLanguageCorrection
      request.minimumTextHeight = min(max(configuration.minimumTextHeight, 0), 1)
      return request
    }

    static func makeRectangleRequest(
      configuration: AppleVisionCardRegionConfiguration
    ) -> VNDetectRectanglesRequest {
      let configuration = configuration.normalized
      let request = VNDetectRectanglesRequest()
      request.maximumObservations = configuration.maximumObservations
      request.minimumConfidence = configuration.minimumConfidence
      request.minimumSize = configuration.minimumSize
      request.quadratureTolerance = configuration.quadratureTolerance

      let minimumLongToShortRatio = max(
        configuration.preferredAspectRatio - configuration.aspectRatioTolerance,
        1
      )
      let maximumLongToShortRatio = max(
        configuration.preferredAspectRatio + configuration.aspectRatioTolerance,
        minimumLongToShortRatio
      )
      request.minimumAspectRatio = Float(1 / maximumLongToShortRatio)
      request.maximumAspectRatio = Float(1 / minimumLongToShortRatio)
      return request
    }

    static func perspectiveCorrectedImage(
      _ image: CIImage,
      candidate: CardRegionCandidate,
      context: CIContext
    ) -> CGImage? {
      let extent = image.extent
      guard
        extent.width.isFinite,
        extent.height.isFinite,
        extent.width > 0,
        extent.height > 0,
        let filter = CIFilter(name: "CIPerspectiveCorrection")
      else {
        return nil
      }

      func imagePoint(_ normalizedPoint: CGPoint) -> CGPoint {
        CGPoint(
          x: extent.minX + normalizedPoint.x * extent.width,
          y: extent.minY + normalizedPoint.y * extent.height
        )
      }

      filter.setValue(image, forKey: kCIInputImageKey)
      filter.setValue(CIVector(cgPoint: imagePoint(candidate.topLeft)), forKey: "inputTopLeft")
      filter.setValue(CIVector(cgPoint: imagePoint(candidate.topRight)), forKey: "inputTopRight")
      filter.setValue(
        CIVector(cgPoint: imagePoint(candidate.bottomLeft)),
        forKey: "inputBottomLeft"
      )
      filter.setValue(
        CIVector(cgPoint: imagePoint(candidate.bottomRight)),
        forKey: "inputBottomRight"
      )
      guard let output = filter.outputImage else { return nil }
      let outputExtent = output.extent.integral
      guard
        outputExtent.width.isFinite,
        outputExtent.height.isFinite,
        outputExtent.width >= 2,
        outputExtent.height >= 2
      else {
        return nil
      }
      return context.createCGImage(output, from: outputExtent)
    }

    static func orientation(from source: CGImageSource) -> CGImagePropertyOrientation {
      let properties =
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      let rawValue = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
      return orientation(fromMetadataValue: rawValue)
    }

    static func orientation(fromMetadataValue rawValue: UInt32?) -> CGImagePropertyOrientation {
      guard let rawValue, (1...8).contains(rawValue) else { return .up }
      return CGImagePropertyOrientation(rawValue: rawValue) ?? .up
    }
  }

  struct IsolatedCardRecognition: Sendable {
    var tokens: [OCRToken]
    var region: AppleVisionDetectedCardRegion
    var selectionScore: Double
  }

  struct CardRegionCandidate: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint
    var confidence: Float
    var sourceSize: CGSize

    init(_ observation: VNRectangleObservation, sourceSize: CGSize) {
      self.init(
        topLeft: observation.topLeft,
        topRight: observation.topRight,
        bottomLeft: observation.bottomLeft,
        bottomRight: observation.bottomRight,
        confidence: observation.confidence,
        sourceSize: sourceSize
      )
    }

    init(
      topLeft: CGPoint,
      topRight: CGPoint,
      bottomLeft: CGPoint,
      bottomRight: CGPoint,
      confidence: Float,
      sourceSize: CGSize = CGSize(width: 1, height: 1)
    ) {
      self.topLeft = topLeft
      self.topRight = topRight
      self.bottomLeft = bottomLeft
      self.bottomRight = bottomRight
      self.confidence = confidence
      self.sourceSize = sourceSize
    }

    var boundingBox: CGRect {
      let points = [topLeft, topRight, bottomLeft, bottomRight]
      let minimumX = points.map(\.x).min() ?? 0
      let maximumX = points.map(\.x).max() ?? 0
      let minimumY = points.map(\.y).min() ?? 0
      let maximumY = points.map(\.y).max() ?? 0
      return CGRect(
        x: minimumX,
        y: minimumY,
        width: maximumX - minimumX,
        height: maximumY - minimumY
      )
    }

    var normalizedBoundingBox: NormalizedBoundingBox {
      let box = CardRegionSelector.clampedUnitBox(boundingBox)
      return NormalizedBoundingBox(
        x: Double(box.origin.x),
        y: Double(box.origin.y),
        width: Double(box.width),
        height: Double(box.height)
      )
    }

    var area: Double {
      let points = [bottomLeft, bottomRight, topRight, topLeft]
      let twiceArea = zip(points, points.dropFirst() + [points[0]]).reduce(0.0) {
        partialResult, pair in
        partialResult
          + Double(pair.0.x * pair.1.y - pair.1.x * pair.0.y)
      }
      return abs(twiceArea) / 2
    }

    var longToShortAspectRatio: Double {
      let horizontalLength =
        (distance(topLeft, topRight) + distance(bottomLeft, bottomRight)) / 2
      let verticalLength =
        (distance(topLeft, bottomLeft) + distance(topRight, bottomRight)) / 2
      let longSide = max(horizontalLength, verticalLength)
      let shortSide = min(horizontalLength, verticalLength)
      guard shortSide > 0 else { return .infinity }
      return longSide / shortSide
    }

    func geometryScore(configuration: AppleVisionCardRegionConfiguration) -> Double {
      let areaDenominator = max(0.40 - configuration.minimumAreaRatio, 0.01)
      let areaScore = Self.clamp(
        (area - configuration.minimumAreaRatio) / areaDenominator
      )
      let aspectDenominator = max(configuration.aspectRatioTolerance, 0.01)
      let aspectScore = Self.clamp(
        1 - abs(longToShortAspectRatio - configuration.preferredAspectRatio)
          / aspectDenominator
      )
      let box = boundingBox
      let centerDistance = hypot(Double(box.midX - 0.5), Double(box.midY - 0.5))
      let centralityScore = Self.clamp(1 - centerDistance / sqrt(0.5))
      let confidenceScore = Self.clamp(Double(confidence))
      return Self.clamp(
        0.45 * areaScore + 0.30 * aspectScore + 0.20 * centralityScore
          + 0.05 * confidenceScore
      )
    }

    func isPlausible(configuration: AppleVisionCardRegionConfiguration) -> Bool {
      let points = [topLeft, topRight, bottomLeft, bottomRight]
      guard
        points.allSatisfy({ point in
          point.x.isFinite && point.y.isFinite
            && (-0.01...1.01).contains(point.x)
            && (-0.01...1.01).contains(point.y)
        }),
        area >= configuration.minimumAreaRatio,
        Double(confidence) >= Double(configuration.minimumConfidence)
      else {
        return false
      }
      let minimumAspectRatio = max(
        configuration.preferredAspectRatio - configuration.aspectRatioTolerance,
        1
      )
      let maximumAspectRatio =
        configuration.preferredAspectRatio + configuration.aspectRatioTolerance
      return (minimumAspectRatio...maximumAspectRatio).contains(longToShortAspectRatio)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> Double {
      hypot(
        Double(first.x - second.x) * Double(sourceSize.width),
        Double(first.y - second.y) * Double(sourceSize.height)
      )
    }

    private static func clamp(_ value: Double) -> Double {
      min(max(value, 0), 1)
    }
  }

  enum CardRegionSelector {
    static func rankedCandidates(
      _ candidates: [CardRegionCandidate],
      configuration: AppleVisionCardRegionConfiguration,
      limit: Int
    ) -> [CardRegionCandidate] {
      let sorted =
        candidates
        .filter { $0.isPlausible(configuration: configuration) }
        .sorted { first, second in
          let firstScore = first.geometryScore(configuration: configuration)
          let secondScore = second.geometryScore(configuration: configuration)
          if abs(firstScore - secondScore) > 0.000_001 {
            return firstScore > secondScore
          }
          if abs(first.area - second.area) > 0.000_001 {
            return first.area > second.area
          }
          if abs(first.boundingBox.minY - second.boundingBox.minY) > 0.000_001 {
            return first.boundingBox.minY < second.boundingBox.minY
          }
          return first.boundingBox.minX < second.boundingBox.minX
        }

      var selected: [CardRegionCandidate] = []
      for candidate in sorted {
        guard !selected.contains(where: { intersectionOverUnion($0, candidate) >= 0.75 }) else {
          continue
        }
        selected.append(candidate)
        if selected.count >= max(limit, 1) { break }
      }
      return selected
    }

    static func selectionScore(geometryScore: Double, textEvidenceScore: Double) -> Double {
      min(max(0.35 * geometryScore + 0.65 * textEvidenceScore, 0), 1)
    }

    static func clampedUnitBox(_ box: CGRect) -> CGRect {
      guard
        box.origin.x.isFinite,
        box.origin.y.isFinite,
        box.width.isFinite,
        box.height.isFinite
      else {
        return .zero
      }
      if box.minX >= 0, box.minY >= 0, box.maxX <= 1, box.maxY <= 1 {
        return box
      }
      let minimumX = min(max(box.minX, 0), 1)
      let maximumX = min(max(box.maxX, 0), 1)
      let minimumY = min(max(box.minY, 0), 1)
      let maximumY = min(max(box.maxY, 0), 1)
      return CGRect(
        x: minimumX,
        y: minimumY,
        width: max(maximumX - minimumX, 0),
        height: max(maximumY - minimumY, 0)
      )
    }

    private static func intersectionOverUnion(
      _ first: CardRegionCandidate,
      _ second: CardRegionCandidate
    ) -> Double {
      let firstBox = clampedUnitBox(first.boundingBox)
      let secondBox = clampedUnitBox(second.boundingBox)
      let intersection = firstBox.intersection(secondBox)
      guard !intersection.isNull, !intersection.isEmpty else { return 0 }
      let intersectionArea = Double(intersection.width * intersection.height)
      let unionArea =
        Double(
          firstBox.width * firstBox.height + secondBox.width * secondBox.height
        ) - intersectionArea
      guard unionArea > 0 else { return 0 }
      return intersectionArea / unionArea
    }
  }

  enum CardTextEvidence {
    static func score(_ lines: [String]) -> Double {
      let normalizedLines =
        lines
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      guard !normalizedLines.isEmpty else { return 0 }

      let joined = normalizedLines.joined(separator: " ")
      let lowercased = joined.lowercased()
      let hasEmail = matches(
        #"[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}"#,
        in: lowercased
      )
      let textWithoutEmails = lowercased.replacingOccurrences(
        of: #"[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}"#,
        with: " ",
        options: .regularExpression
      )
      let hasWebsite = matches(
        #"(?:https?://|www\.)[^\s]+|\b[a-z0-9][a-z0-9.\-]+\.(?:com|org|net|io|co|kr|sg|group)\b"#,
        in: textWithoutEmails
      )
      let hasPhone = normalizedLines.contains(where: isPhoneLine)
      let hasTitle = containsAny(
        lowercased,
        terms: [
          "ceo", "cto", "founder", "chairman", "president", "principal", "manager",
          "director", "consultant", "officer", "대표", "팀장", "부장", "본부장", "센터장",
          "주무관", "전문위원", "수석심사역",
        ]
      )
      let hasContactLabel = containsAny(
        lowercased,
        terms: [
          "mobile", "cell", "phone", "tel", "fax", "email", "e-mail", "web", "모바일",
          "전화", "팩스", "이메일",
        ]
      )
      let hasAddress = containsAny(
        lowercased,
        terms: [
          "address", "road", "street", "building", "tower", "seoul", "singapore",
          "philippines", "amsterdam", "서울", "경기도", "경남", "전북", "특별자치도",
        ]
      )
      let hasNameLikeLine = normalizedLines.contains(where: isNameLikeLine)

      var value = 0.0
      if hasEmail { value += 0.24 }
      if hasPhone { value += 0.20 }
      if hasWebsite { value += 0.14 }
      if hasTitle { value += 0.13 }
      if hasContactLabel { value += 0.06 }
      if hasAddress { value += 0.09 }
      if hasNameLikeLine { value += 0.06 }
      if normalizedLines.count >= 4 { value += 0.04 }

      let contactAnchorCount = [hasEmail, hasPhone, hasWebsite].filter { $0 }.count
      if contactAnchorCount >= 2 { value += 0.08 }
      if contactAnchorCount >= 1 && (hasTitle || hasNameLikeLine) { value += 0.05 }
      return min(value, 1)
    }

    private static func isPhoneLine(_ text: String) -> Bool {
      let lowercased = text.lowercased()
      let digits = lowercased.filter(\.isNumber)
      guard (7...15).contains(digits.count) else { return false }
      if containsAny(
        lowercased,
        terms: ["mobile", "cell", "phone", "tel", "fax", "모바일", "전화", "팩스"]
      ) {
        return true
      }
      let letters = lowercased.filter(\.isLetter)
      return letters.count <= 4
        && (lowercased.contains("+")
          || lowercased.contains("-")
          || lowercased.contains(" ")
          || lowercased.contains("."))
    }

    private static func isNameLikeLine(_ text: String) -> Bool {
      let lowercased = text.lowercased()
      guard
        !lowercased.contains("@"),
        !lowercased.contains("www"),
        lowercased.filter(\.isNumber).count <= 1,
        !containsAny(
          lowercased,
          terms: [
            "mobile", "phone", "email", "address", "street", "road", "building", "모바일",
            "이메일", "주소",
          ]
        )
      else {
        return false
      }
      let words = lowercased.split(whereSeparator: { !$0.isLetter })
      return (2...6).contains(words.count)
    }

    private static func containsAny(_ text: String, terms: [String]) -> Bool {
      terms.contains(where: text.contains)
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
      text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
  }

  /// Converts Apple Vision observations without exposing Vision types to `CardFieldCore`.
  public enum AppleVisionAdapter {
    public static func tokens(
      from observations: [VNRecognizedTextObservation],
      language: String? = nil
    ) -> [OCRToken] {
      tokens(from: recognizedLines(from: observations), language: language)
    }

    static func recognizedLines(
      from observations: [VNRecognizedTextObservation]
    ) -> [RecognizedLine] {
      observations.compactMap { observation -> RecognizedLine? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        return RecognizedLine(
          text: candidate.string,
          boundingBox: observation.boundingBox,
          confidence: candidate.confidence
        )
      }
    }

    static func tokens(
      from recognizedLines: [RecognizedLine],
      language: String? = nil
    ) -> [OCRToken] {
      recognizedLines.enumerated().compactMap { index, line in
        guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return nil
        }
        guard
          line.boundingBox.origin.x.isFinite,
          line.boundingBox.origin.y.isFinite,
          line.boundingBox.width.isFinite,
          line.boundingBox.height.isFinite,
          line.boundingBox.width >= 0,
          line.boundingBox.height >= 0,
          line.confidence.isFinite
        else {
          return nil
        }
        let box = CardRegionSelector.clampedUnitBox(line.boundingBox)
        return OCRToken(
          id: String(format: "vision-%04d", index + 1),
          text: line.text,
          boundingBox: NormalizedBoundingBox(
            x: Double(box.origin.x),
            y: Double(box.origin.y),
            width: Double(box.width),
            height: Double(box.height)
          ),
          confidence: min(max(Double(line.confidence), 0), 1),
          language: language
        )
      }
    }
  }

  struct RecognizedLine: Equatable, Sendable {
    var text: String
    var boundingBox: CGRect
    var confidence: Float
  }
#else
  /// This target can be resolved on non-Apple platforms, but scanning requires Apple Vision.
  public enum AppleVisionAdapter {}
#endif
