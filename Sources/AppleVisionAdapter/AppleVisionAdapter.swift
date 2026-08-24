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

    /// Minimum long-edge pixel size of a perspective-corrected card before OCR,
    /// clamped to `0...8192`. Small corrections are upscaled; `0` disables scaling.
    public var minimumCorrectedLongEdge: Int

    /// Whether attention-based saliency proposes a candidate region when rectangle
    /// detection finds nothing. Text-evidence gating still applies.
    public var usesSaliencyFallback: Bool

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
      minimumTextEvidenceScore: Double = 0.45,
      minimumCorrectedLongEdge: Int = 1_400,
      usesSaliencyFallback: Bool = true
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
      self.minimumCorrectedLongEdge = min(max(minimumCorrectedLongEdge, 0), 8_192)
      self.usesSaliencyFallback = usesSaliencyFallback
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
        minimumTextEvidenceScore: minimumTextEvidenceScore,
        minimumCorrectedLongEdge: minimumCorrectedLongEdge,
        usesSaliencyFallback: usesSaliencyFallback
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
    ///
    /// When `dualPassRecognition` is enabled this value governs the corrected pass;
    /// strict-syntax regions such as emails, phones, and URLs are additionally read
    /// once without correction so that proper nouns survive.
    public var usesLanguageCorrection: Bool

    /// The minimum text height relative to the image height, clamped to `0...1`.
    public var minimumTextHeight: Float

    /// An optional BCP 47 tag copied to every emitted token as a host-provided hint.
    /// Vision does not expose a detected language for individual recognized candidates.
    public var tokenLanguage: String?

    /// Foreground-card isolation applied before text recognition.
    public var cardRegion: AppleVisionCardRegionConfiguration

    /// Local image enhancement applied before recognition.
    public var preprocessing: AppleVisionPreprocessingConfiguration

    /// Pinned `VNRecognizeTextRequest` revision, clamped to `1...3`. Pinning keeps
    /// recognition stable across operating-system updates on supported runtimes.
    public var recognitionRevision: Int

    /// Number of ranked readings requested per line, clamped to `1...10`. Readings
    /// beyond the first populate `OCRToken.alternatives` and dual-pass merging.
    public var candidateCount: Int

    /// Whether each region is recognized twice — with and without language
    /// correction — and merged deterministically. Doubles recognition latency.
    public var dualPassRecognition: Bool

    /// Whether low-confidence lines are re-recognized from an upscaled crop.
    public var performsTargetedReRecognition: Bool

    /// Lines at or below this confidence receive targeted re-recognition,
    /// clamped to `0...1`.
    public var targetedReRecognitionConfidenceLimit: Double

    /// Whether tokens without an explicit hint receive script-based BCP 47 tags
    /// inferred from Unicode ranges.
    public var infersTokenLanguages: Bool

    public init(
      recognitionLevel: RecognitionLevel = .accurate,
      recognitionLanguages: [String] = [],
      automaticallyDetectsLanguage: Bool = true,
      usesLanguageCorrection: Bool = true,
      minimumTextHeight: Float = 0,
      tokenLanguage: String? = nil,
      cardRegion: AppleVisionCardRegionConfiguration = AppleVisionCardRegionConfiguration(),
      preprocessing: AppleVisionPreprocessingConfiguration =
        AppleVisionPreprocessingConfiguration(),
      recognitionRevision: Int = 3,
      candidateCount: Int = 3,
      dualPassRecognition: Bool = true,
      performsTargetedReRecognition: Bool = true,
      targetedReRecognitionConfidenceLimit: Double = 0.35,
      infersTokenLanguages: Bool = true
    ) {
      self.recognitionLevel = recognitionLevel
      self.recognitionLanguages = recognitionLanguages
      self.automaticallyDetectsLanguage = automaticallyDetectsLanguage
      self.usesLanguageCorrection = usesLanguageCorrection
      self.minimumTextHeight = min(max(minimumTextHeight, 0), 1)
      self.tokenLanguage = tokenLanguage
      self.cardRegion = cardRegion
      self.preprocessing = preprocessing
      self.recognitionRevision = min(max(recognitionRevision, 1), 3)
      self.candidateCount = min(max(candidateCount, 1), 10)
      self.dualPassRecognition = dualPassRecognition
      self.performsTargetedReRecognition = performsTargetedReRecognition
      self.targetedReRecognitionConfidenceLimit = min(
        max(targetedReRecognitionConfidenceLimit, 0), 1)
      self.infersTokenLanguages = infersTokenLanguages
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

  /// Provider-neutral OCR tokens produced from one image, without business-card
  /// field classification.
  ///
  /// General document hosts consume `tokens` and own any downstream
  /// interpretation, review, or storage. No `CardFieldClassifier` runs on this
  /// path, so `.classificationFailed` never originates from a token scan.
  public struct AppleVisionTokenScanResult: Equatable, Sendable {
    public var tokens: [OCRToken]
    public var cardRegionSelection: AppleVisionCardRegionSelection

    public init(
      tokens: [OCRToken],
      cardRegionSelection: AppleVisionCardRegionSelection
    ) {
      self.tokens = tokens
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

  /// Runs Apple Vision locally and emits recognized text either with business-card
  /// field suggestions (`scan`) or as provider-neutral tokens (`scanTokens`).
  ///
  /// Both paths are synchronous; hosts should call them away from latency-sensitive
  /// UI work. The scanner does not retain the image, persist results, or perform
  /// network requests.
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
      let decoded = try Self.decodedImage(imageData)
      return try scanImage(decoded.image, orientation: orientation ?? decoded.exifOrientation)
    }

    /// Scans a decoded image. `orientation` describes how its pixels must rotate to become upright.
    public func scan(
      cgImage: CGImage,
      orientation: CGImagePropertyOrientation = .up
    ) throws -> AppleVisionScanResult {
      try scanImage(cgImage, orientation: orientation)
    }

    /// Recognizes encoded image bytes as provider-neutral tokens without field classification.
    ///
    /// Shares the identical pipeline with `scan(imageData:)` up through token
    /// production — enhancement, optional card isolation, dual-pass recognition,
    /// targeted re-recognition, and language inference — then returns without
    /// invoking `CardFieldClassifier`.
    public func scanTokens(
      imageData: Data,
      orientation: CGImagePropertyOrientation? = nil
    ) throws -> AppleVisionTokenScanResult {
      let decoded = try Self.decodedImage(imageData)
      return try performTokenRecognition(
        decoded.image,
        orientation: orientation ?? decoded.exifOrientation
      )
    }

    /// Recognizes a decoded image as provider-neutral tokens without field classification.
    public func scanTokens(
      cgImage: CGImage,
      orientation: CGImagePropertyOrientation = .up
    ) throws -> AppleVisionTokenScanResult {
      try performTokenRecognition(cgImage, orientation: orientation)
    }

    private static func decodedImage(_ data: Data) throws -> (
      image: CGImage,
      exifOrientation: CGImagePropertyOrientation
    ) {
      guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        CGImageSourceGetCount(source) > 0,
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        throw AppleVisionScanError.invalidImageData
      }
      return (image, orientation(from: source))
    }

    private func scanImage(
      _ image: CGImage,
      orientation: CGImagePropertyOrientation
    ) throws -> AppleVisionScanResult {
      let tokens = try performTokenRecognition(image, orientation: orientation)
      return try makeResult(
        from: tokens.tokens,
        cardRegionSelection: tokens.cardRegionSelection
      )
    }

    /// Generic OCR path shared by `scan` and `scanTokens`: enhancement, card-region
    /// handling, recognition, merging, refinement, and language tags.
    private func performTokenRecognition(
      _ image: CGImage,
      orientation: CGImagePropertyOrientation
    ) throws -> AppleVisionTokenScanResult {
      let working = preparedWorkingImage(image, orientation: orientation)

      var tokens: [OCRToken]
      var selection: AppleVisionCardRegionSelection
      if configuration.cardRegion.mode == .automatic,
        let isolatedResult = isolatedCardResult(from: working)
      {
        tokens = isolatedResult.tokens
        selection = .isolated(isolatedResult.region)
      } else {
        var recognized = try recognizeTokens(in: working, orientation: .up)
        recognized = refineLowConfidenceTokens(recognized, in: working)
        tokens = recognized
        selection =
          configuration.cardRegion.mode == .disabled ? .disabled : .fullImageFallback
      }

      guard !tokens.isEmpty else {
        throw AppleVisionScanError.noRecognizedText
      }
      return AppleVisionTokenScanResult(tokens: tokens, cardRegionSelection: selection)
    }

    /// Produces one upright, enhanced image shared by detection, recognition, and crops.
    private func preparedWorkingImage(
      _ image: CGImage,
      orientation: CGImagePropertyOrientation
    ) -> CGImage {
      if orientation != .up {
        let oriented = CIImage(cgImage: image).oriented(
          forExifOrientation: Int32(orientation.rawValue)
        )
        if let upright = ImagePreprocessor.sharedContext.createCGImage(
          oriented, from: oriented.extent
        ) {
          return ImagePreprocessor.preprocess(upright, configuration: configuration.preprocessing)
        }
        return image
      }
      return ImagePreprocessor.preprocess(image, configuration: configuration.preprocessing)
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

      let primaryLines = AppleVisionAdapter.recognizedLines(
        from: request.results ?? [],
        candidateCount: configuration.candidateCount
      )
      guard configuration.dualPassRecognition, configuration.recognitionLevel == .accurate else {
        return primaryLines
      }

      var oppositeConfiguration = configuration
      oppositeConfiguration.usesLanguageCorrection.toggle()
      let oppositeRequest = Self.makeRequest(configuration: oppositeConfiguration)
      let oppositeHandler = VNImageRequestHandler(
        cgImage: image,
        orientation: orientation,
        options: [:]
      )
      do {
        try oppositeHandler.perform([oppositeRequest])
      } catch {
        return primaryLines
      }
      let oppositeLines = AppleVisionAdapter.recognizedLines(
        from: oppositeRequest.results ?? [],
        candidateCount: configuration.candidateCount
      )

      let corrected =
        configuration.usesLanguageCorrection ? primaryLines : oppositeLines
      let uncorrected =
        configuration.usesLanguageCorrection ? oppositeLines : primaryLines
      return Self.mergedLines(corrected: corrected, uncorrected: uncorrected)
    }

    private func recognizeTokens(
      in image: CGImage,
      orientation: CGImagePropertyOrientation
    ) throws -> [OCRToken] {
      let lines = try recognizeLines(in: image, orientation: orientation)
      return AppleVisionAdapter.tokens(
        from: lines,
        language: configuration.tokenLanguage,
        infersLanguages: configuration.infersTokenLanguages
      )
    }

    /// Re-recognizes an upscaled crop around weak lines and keeps improvements.
    ///
    /// Any failure returns the original tokens: targeted refinement must never
    /// fail a scan that already produced usable text.
    private func refineLowConfidenceTokens(
      _ tokens: [OCRToken],
      in working: CGImage
    ) -> [OCRToken] {
      let limit = configuration.targetedReRecognitionConfidenceLimit
      let weakTokens = tokens.filter { $0.confidence <= limit && $0.text.count >= 2 }
      guard configuration.performsTargetedReRecognition, limit > 0, !weakTokens.isEmpty
      else { return tokens }

      let unionBox = weakTokens.dropFirst().reduce(weakTokens[0].boundingBox) { partial, token in
        let minX = min(partial.x, token.boundingBox.x)
        let minY = min(partial.y, token.boundingBox.y)
        let maxX = max(partial.x + partial.width, token.boundingBox.x + token.boundingBox.width)
        let maxY = max(partial.y + partial.height, token.boundingBox.y + token.boundingBox.height)
        return NormalizedBoundingBox(
          x: minX,
          y: minY,
          width: max(maxX - minX, 0),
          height: max(maxY - minY, 0)
        )
      }
      guard
        let cropRect = Self.pixelCropRect(
          for: unionBox,
          imageSize: CGSize(width: working.width, height: working.height),
          padding: 0.02
        ),
        let cropped = working.cropping(to: cropRect)
      else { return tokens }

      let refinedSource =
        ImagePreprocessor.upscale(cropped, targetLongEdge: 1_600) ?? cropped
      guard
        let refinedLines = try? recognizeLines(in: refinedSource, orientation: .up),
        !refinedLines.isEmpty
      else { return tokens }

      let imageSize = CGSize(width: working.width, height: working.height)
      let cropFrame = Self.normalizedFrame(of: cropRect, in: imageSize)

      var refined = tokens
      for index in refined.indices where refined[index].confidence <= limit {
        let token = refined[index]
        let inflated = Self.inflated(token.boundingBox, fraction: 0.5)
        var best: RecognizedLine?
        for line in refinedLines {
          let absolute = Self.absoluteBox(line.boundingBox, within: cropFrame)
          let inflatedBox = CGRect(
            x: inflated.x,
            y: inflated.y,
            width: inflated.width,
            height: inflated.height
          )
          guard Self.centersOverlap(absolute, inflatedBox) else { continue }
          if best == nil || line.confidence > best!.confidence { best = line }
        }
        guard let replacement = best, Double(replacement.confidence) > token.confidence
        else { continue }

        refined[index].text = replacement.text
        refined[index].confidence = min(max(Double(replacement.confidence), 0), 1)
        var alternatives = refined[index].alternatives
        alternatives.append(contentsOf: [token.text] + replacement.alternatives)
        var seen: Set<String> = [replacement.text]
        refined[index].alternatives = alternatives.filter { seen.insert($0).inserted }
      }
      return refined
    }

    /// Internal hook exercising targeted refinement without a full scan.
    func refinedForTesting(_ tokens: [OCRToken], in image: CGImage) -> [OCRToken] {
      refineLowConfidenceTokens(tokens, in: image)
    }

    private func isolatedCardResult(from working: CGImage) -> IsolatedCardRecognition? {
      let ciImage = CIImage(cgImage: working)
      let regionConfiguration = configuration.cardRegion.normalized
      let request = Self.makeRectangleRequest(configuration: regionConfiguration)
      let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        return nil
      }

      var ranked = CardRegionSelector.rankedCandidates(
        (request.results ?? []).map {
          CardRegionCandidate($0, sourceSize: ciImage.extent.size)
        },
        configuration: regionConfiguration,
        limit: regionConfiguration.maximumTextRecognitionCandidates
      )
      if ranked.isEmpty, regionConfiguration.usesSaliencyFallback,
        let salient = CardRegionSelector.saliencyCandidate(
          from: ciImage,
          configuration: regionConfiguration
        )
      {
        ranked = [salient]
      }
      guard !ranked.isEmpty else { return nil }

      let context = ImagePreprocessor.sharedContext
      var best: IsolatedCardRecognition?
      for candidate in ranked {
        guard
          let correctedImage = Self.perspectiveCorrectedImage(
            ciImage,
            candidate: candidate,
            context: context,
            minimumLongEdge: regionConfiguration.minimumCorrectedLongEdge
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
        var tokens = AppleVisionAdapter.tokens(
          from: lines,
          language: configuration.tokenLanguage,
          infersLanguages: configuration.infersTokenLanguages
        )
        tokens = refineLowConfidenceTokens(tokens, in: correctedImage)
        guard !tokens.isEmpty else { continue }

        let selectionScore = CardRegionSelector.selectionScore(
          geometryScore: candidate.geometryScore(configuration: regionConfiguration),
          textEvidenceScore: textEvidenceScore
        )
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
      request.revision = min(max(configuration.recognitionRevision, 1), 3)
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
      context: CIContext,
      minimumLongEdge: Int = 0
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
      guard var output = filter.outputImage else { return nil }

      if minimumLongEdge > 0 {
        let target = CGFloat(minimumLongEdge)
        var longEdge = max(output.extent.width, output.extent.height)
        if longEdge.isFinite, longEdge > 0, longEdge < target {
          let ratio = target / longEdge
          if ratio.isFinite, ratio > 1 {
            output = output.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
            // Integral rounding can shave a pixel or two; top up once so the
            // produced long edge reliably meets the configured minimum.
            longEdge = max(output.extent.width, output.extent.height)
            if longEdge.isFinite, longEdge > 0, longEdge < target {
              let topUp = target / longEdge
              if topUp.isFinite, topUp > 1 {
                output = output.transformed(by: CGAffineTransform(scaleX: topUp, y: topUp))
              }
            }
          }
        }
      }

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

    /// Deterministically merges a language-corrected pass with an uncorrected pass.
    ///
    /// Regions are paired by geometric overlap. Strict-syntax text (emails, phones,
    /// URLs) takes the uncorrected reading so language correction cannot rewrite
    /// proper nouns or addresses; everything else keeps the corrected reading.
    /// Unpaired lines from both passes are retained in stable order.
    static func mergedLines(
      corrected: [RecognizedLine],
      uncorrected: [RecognizedLine]
    ) -> [RecognizedLine] {
      var consumed = Set<Int>()
      var result: [RecognizedLine] = []
      for base in corrected {
        var matchIndex: Int?
        var bestOverlap = 0.45
        for index in uncorrected.indices where !consumed.contains(index) {
          let overlap = overlapRatio(base.boundingBox, uncorrected[index].boundingBox)
          if overlap > bestOverlap {
            bestOverlap = overlap
            matchIndex = index
          }
        }
        if let matchIndex {
          consumed.insert(matchIndex)
          result.append(mergingLine(base, uncorrected[matchIndex]))
        } else {
          result.append(base)
        }
      }

      let remaining =
        uncorrected.enumerated()
        .filter { !consumed.contains($0.offset) }
        .map(\.element)
        .sorted {
          if $0.boundingBox.minY != $1.boundingBox.minY {
            return $0.boundingBox.minY > $1.boundingBox.minY
          }
          return $0.boundingBox.minX < $1.boundingBox.minX
        }
      result.append(contentsOf: remaining)
      return result
    }

    static func mergingLine(
      _ corrected: RecognizedLine,
      _ uncorrected: RecognizedLine
    ) -> RecognizedLine {
      let chosen = prefersUncorrectedText(uncorrected.text) ? uncorrected : corrected
      var merged = chosen
      merged.boundingBox = corrected.boundingBox
      merged.confidence = max(corrected.confidence, uncorrected.confidence)

      let readings =
        [
          corrected.text, uncorrected.text,
        ] + corrected.alternatives + uncorrected.alternatives
      var seen: Set<String> = [merged.text]
      merged.alternatives = Array(readings.filter { seen.insert($0).inserted }.prefix(4))
      return merged
    }

    nonisolated(unsafe) private static let emailPattern =
      /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/

    private static let domainSuffixes = [
      "com", "org", "net", "io", "co", "kr", "jp", "cn", "de", "fr", "uk", "sg",
      "us", "group", "studio", "works",
    ]

    /// True for readings whose syntax language correction must not rewrite.
    static func prefersUncorrectedText(_ text: String) -> Bool {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return false }
      if trimmed.contains("@"), trimmed.firstMatch(of: emailPattern) != nil { return true }
      if trimmed.filter(\.isNumber).count >= 7 { return true }
      let lowered = trimmed.lowercased()
      if lowered.hasPrefix("www.") || lowered.contains("http") { return true }
      return domainSuffixes.contains { lowered.hasSuffix(".\($0)") }
    }

    static func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> Double {
      let intersection = lhs.intersection(rhs)
      guard !intersection.isNull, !intersection.isEmpty else { return 0 }
      let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
      guard smallerArea > 0 else { return 0 }
      return Double(intersection.width * intersection.height) / Double(smallerArea)
    }

    /// Converts a bottom-left normalized union box into a padded pixel crop rect.
    static func pixelCropRect(
      for box: NormalizedBoundingBox,
      imageSize: CGSize,
      padding: Double
    ) -> CGRect? {
      let minX = max(Double(box.x) - padding, 0)
      let minY = max(Double(box.y) - padding, 0)
      let maxX = min(Double(box.x + box.width) + padding, 1)
      let maxY = min(Double(box.y + box.height) + padding, 1)
      guard maxX > minX, maxY > minY else { return nil }

      let bounds = CGRect(origin: .zero, size: imageSize)
      let crop = CGRect(
        x: minX * imageSize.width,
        y: (1 - maxY) * imageSize.height,
        width: (maxX - minX) * imageSize.width,
        height: (maxY - minY) * imageSize.height
      ).integral
      let intersection = crop.intersection(bounds)
      guard !intersection.isNull, intersection.width >= 2, intersection.height >= 2 else {
        return nil
      }
      return intersection
    }

    /// Converts a top-left pixel rect into a bottom-left normalized frame.
    static func normalizedFrame(of pixelRect: CGRect, in imageSize: CGSize) -> CGRect {
      guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
      return CGRect(
        x: pixelRect.minX / imageSize.width,
        y: (imageSize.height - pixelRect.maxY) / imageSize.height,
        width: pixelRect.width / imageSize.width,
        height: pixelRect.height / imageSize.height
      )
    }

    static func inflated(_ box: NormalizedBoundingBox, fraction: Double) -> NormalizedBoundingBox {
      let padX = box.width * fraction
      let padY = box.height * fraction
      let x = max(box.x - padX, 0)
      let y = max(box.y - padY, 0)
      return NormalizedBoundingBox(
        x: x,
        y: y,
        width: min(box.x + box.width + padX, 1) - x,
        height: min(box.y + box.height + padY, 1) - y
      )
    }

    /// Maps a crop-relative normalized box into full-image coordinates.
    static func absoluteBox(_ relative: CGRect, within frame: CGRect) -> CGRect {
      CGRect(
        x: frame.minX + relative.minX * frame.width,
        y: frame.minY + relative.minY * frame.height,
        width: relative.width * frame.width,
        height: relative.height * frame.height
      )
    }

    static func centersOverlap(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
      guard lhs.width >= 0, lhs.height >= 0, rhs.width >= 0, rhs.height >= 0 else { return false }
      let grown = rhs.insetBy(dx: -rhs.width * 0.25, dy: -rhs.height * 0.5)
      return grown.contains(CGPoint(x: lhs.midX, y: lhs.midY))
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
      var twiceArea = 0.0
      for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        let crossProduct = current.x * next.y - next.x * current.y
        twiceArea += Double(crossProduct)
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

    /// Proposes one card-shaped candidate centered on the most salient object
    /// when rectangle detection produced nothing.
    ///
    /// The salient box is expanded and reshaped toward the preferred aspect ratio,
    /// then clamped to the unit square. Confidence is deliberately capped so a
    /// rectangle observation always outranks the same geometry, and downstream
    /// contact-text evidence remains mandatory before isolation wins.
    static func saliencyCandidate(
      from image: CIImage,
      configuration: AppleVisionCardRegionConfiguration
    ) -> CardRegionCandidate? {
      let request = VNGenerateAttentionBasedSaliencyImageRequest()
      let handler = VNImageRequestHandler(ciImage: image, options: [:])
      guard (try? handler.perform([request])) != nil,
        let observation = request.results?.first,
        let salient = observation.salientObjects?.first(where: { $0.confidence > 0 })
      else {
        return nil
      }
      return saliencyCandidate(
        fromSalientBox: salient.boundingBox,
        confidence: salient.confidence,
        configuration: configuration
      )
    }

    static func saliencyCandidate(
      fromSalientBox box: CGRect,
      confidence: Float = 1,
      configuration: AppleVisionCardRegionConfiguration
    ) -> CardRegionCandidate? {
      let salient = clampedUnitBox(box)
      guard salient.width > 0, salient.height > 0 else { return nil }

      let expansion = CGFloat(1.6)
      var width = min(max(salient.width * expansion, 0.30), 1)
      var height = min(max(salient.height * expansion, 0.18), 1)
      let preferredRatio = CGFloat(configuration.preferredAspectRatio)
      if preferredRatio >= width / height {
        height = width / preferredRatio
      } else {
        width = height * preferredRatio
      }
      if width > 1 {
        width = 1
        height = width / preferredRatio
      }
      if height > 1 {
        height = 1
        width = height * preferredRatio
      }

      let center = CGPoint(x: salient.midX, y: salient.midY)
      let frame = clampedUnitBox(
        CGRect(
          x: center.x - width / 2,
          y: center.y - height / 2,
          width: width,
          height: height
        )
      )
      guard frame.width >= CGFloat(configuration.minimumSize),
        frame.height * preferredRatio >= CGFloat(configuration.minimumSize)
          || frame.width >= CGFloat(configuration.minimumSize)
      else { return nil }

      return CardRegionCandidate(
        topLeft: CGPoint(x: frame.minX, y: frame.maxY),
        topRight: CGPoint(x: frame.maxX, y: frame.maxY),
        bottomLeft: CGPoint(x: frame.minX, y: frame.minY),
        bottomRight: CGPoint(x: frame.maxX, y: frame.minY),
        confidence: min(max(confidence * 0.75, 0), 0.75),
        sourceSize: CGSize(width: 1, height: 1)
      )
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
    nonisolated(unsafe) private static let emailPattern = /[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}/

    nonisolated(unsafe) private static let websitePattern =
      /(?:https?:\/\/|www\.)\S+|\b[a-z0-9][a-z0-9.\-]+\.(?:com|org|net|io|co|kr|sg|group)\b/

    static func score(_ lines: [String]) -> Double {
      let normalizedLines =
        lines
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      guard !normalizedLines.isEmpty else { return 0 }

      let joined = normalizedLines.joined(separator: " ")
      let lowercased = joined.lowercased()
      let hasEmail = lowercased.contains(emailPattern)
      let textWithoutEmails = lowercased.replacing(emailPattern, with: " ")
      let hasWebsite = textWithoutEmails.contains(websitePattern)
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
  }

  /// Converts Apple Vision observations without exposing Vision types to `CardFieldCore`.
  public enum AppleVisionAdapter {
    public static func tokens(
      from observations: [VNRecognizedTextObservation],
      language: String? = nil
    ) -> [OCRToken] {
      tokens(
        from: recognizedLines(from: observations),
        language: language,
        infersLanguages: false
      )
    }

    static func recognizedLines(
      from observations: [VNRecognizedTextObservation],
      candidateCount: Int = 1
    ) -> [RecognizedLine] {
      observations.compactMap { observation -> RecognizedLine? in
        let candidates = observation.topCandidates(max(candidateCount, 1))
        guard let primary = candidates.first else { return nil }
        return RecognizedLine(
          text: primary.string,
          boundingBox: observation.boundingBox,
          confidence: primary.confidence,
          alternatives: candidates.dropFirst().map(\.string)
        )
      }
    }

    /// Builds core tokens. `infersLanguages` labels unhinted tokens with a
    /// script-based BCP 47 tag when no explicit `language` is supplied.
    static func tokens(
      from recognizedLines: [RecognizedLine],
      language: String? = nil,
      infersLanguages: Bool = false
    ) -> [OCRToken] {
      var tokens = recognizedLines.enumerated().compactMap { index, line -> OCRToken? in
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
        var seen: Set<String> = [line.text.trimmingCharacters(in: .whitespacesAndNewlines)]
        var alternatives: [String] = []
        for reading in line.alternatives {
          let trimmed = reading.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
          alternatives.append(reading)
        }
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
          alternatives: alternatives
        )
      }
      if language != nil || infersLanguages {
        TokenLanguageInference.apply(to: &tokens, hint: language)
      }
      return tokens
    }
  }

  struct RecognizedLine: Equatable, Sendable {
    var text: String
    var boundingBox: CGRect
    var confidence: Float
    var alternatives: [String] = []
  }

  extension AppleVisionScanner {
    /// Asynchronously scans encoded image bytes on a background task.
    ///
    /// Equivalent to the synchronous `scan(imageData:)`, but never blocks the
    /// calling actor. Vision recognition remains local and synchronous inside
    /// the detached task.
    public func scanAsync(
      imageData: Data,
      orientation: CGImagePropertyOrientation? = nil
    ) async throws -> AppleVisionScanResult {
      let task = Task.detached(priority: .userInitiated) {
        try self.scan(imageData: imageData, orientation: orientation)
      }
      return try await task.value
    }

    /// Asynchronously scans a decoded image on a background task.
    public func scanAsync(
      cgImage: CGImage,
      orientation: CGImagePropertyOrientation = .up
    ) async throws -> AppleVisionScanResult {
      let boxed = ImmutableCGImage(cgImage)
      let task = Task.detached(priority: .userInitiated) {
        try self.scan(cgImage: boxed.value, orientation: orientation)
      }
      return try await task.value
    }

    /// Asynchronously recognizes encoded image bytes on a background task without
    /// classification.
    ///
    /// Equivalent to the synchronous `scanTokens(imageData:)`, but never blocks
    /// the calling actor.
    public func scanTokensAsync(
      imageData: Data,
      orientation: CGImagePropertyOrientation? = nil
    ) async throws -> AppleVisionTokenScanResult {
      let task = Task.detached(priority: .userInitiated) {
        try self.scanTokens(imageData: imageData, orientation: orientation)
      }
      return try await task.value
    }

    /// Asynchronously recognizes a decoded image on a background task without
    /// classification.
    public func scanTokensAsync(
      cgImage: CGImage,
      orientation: CGImagePropertyOrientation = .up
    ) async throws -> AppleVisionTokenScanResult {
      let boxed = ImmutableCGImage(cgImage)
      let task = Task.detached(priority: .userInitiated) {
        try self.scanTokens(cgImage: boxed.value, orientation: orientation)
      }
      return try await task.value
    }
  }

  /// Bridges immutable Core Graphics images into strict-concurrency contexts.
  ///
  /// The image is treated as read-only for the duration of one scan; the adapter
  /// neither mutates pixels nor stores the reference beyond the call.
  struct ImmutableCGImage: @unchecked Sendable {
    var value: CGImage

    init(_ value: CGImage) {
      self.value = value
    }
  }
#else
  /// This target can be resolved on non-Apple platforms, but scanning requires Apple Vision.
  public enum AppleVisionAdapter {}
#endif
