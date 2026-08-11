import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import ImageIO
  import Vision

  /// Configuration for local text recognition of an upright business-card front.
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

    public init(
      recognitionLevel: RecognitionLevel = .accurate,
      recognitionLanguages: [String] = [],
      automaticallyDetectsLanguage: Bool = true,
      usesLanguageCorrection: Bool = true,
      minimumTextHeight: Float = 0,
      tokenLanguage: String? = nil
    ) {
      self.recognitionLevel = recognitionLevel
      self.recognitionLanguages = recognitionLanguages
      self.automaticallyDetectsLanguage = automaticallyDetectsLanguage
      self.usesLanguageCorrection = usesLanguageCorrection
      self.minimumTextHeight = min(max(minimumTextHeight, 0), 1)
      self.tokenLanguage = tokenLanguage
    }
  }

  /// The provider-neutral OCR tokens and structured suggestions produced from one card front.
  public struct AppleVisionScanResult: Equatable, Sendable {
    public var tokens: [OCRToken]
    public var fields: CardFieldResult

    public init(tokens: [OCRToken], fields: CardFieldResult) {
      self.tokens = tokens
      self.fields = fields
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
        CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
      else {
        throw AppleVisionScanError.invalidImageData
      }

      let resolvedOrientation = orientation ?? Self.orientation(from: source)
      let handler = VNImageRequestHandler(
        data: imageData,
        orientation: resolvedOrientation,
        options: [:]
      )
      return try scan(using: handler)
    }

    /// Scans a decoded image. `orientation` describes how its pixels must rotate to become upright.
    public func scan(
      cgImage: CGImage,
      orientation: CGImagePropertyOrientation = .up
    ) throws -> AppleVisionScanResult {
      let handler = VNImageRequestHandler(
        cgImage: cgImage,
        orientation: orientation,
        options: [:]
      )
      return try scan(using: handler)
    }

    private func scan(using handler: VNImageRequestHandler) throws -> AppleVisionScanResult {
      let request = Self.makeRequest(configuration: configuration)
      do {
        try handler.perform([request])
      } catch {
        throw AppleVisionScanError.recognitionFailed(error.localizedDescription)
      }

      let tokens = AppleVisionAdapter.tokens(
        from: request.results ?? [],
        language: configuration.tokenLanguage
      )
      return try makeResult(from: tokens)
    }

    func makeResult(from tokens: [OCRToken]) throws -> AppleVisionScanResult {
      guard !tokens.isEmpty else {
        throw AppleVisionScanError.noRecognizedText
      }

      do {
        return AppleVisionScanResult(tokens: tokens, fields: try classifier.classify(tokens))
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
      request.minimumTextHeight = configuration.minimumTextHeight
      return request
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

  /// Converts Apple Vision observations without exposing Vision types to `CardFieldCore`.
  public enum AppleVisionAdapter {
    public static func tokens(
      from observations: [VNRecognizedTextObservation],
      language: String? = nil
    ) -> [OCRToken] {
      let recognizedLines = observations.compactMap { observation -> RecognizedLine? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        return RecognizedLine(
          text: candidate.string,
          boundingBox: observation.boundingBox,
          confidence: candidate.confidence
        )
      }
      return tokens(from: recognizedLines, language: language)
    }

    static func tokens(
      from recognizedLines: [RecognizedLine],
      language: String? = nil
    ) -> [OCRToken] {
      recognizedLines.enumerated().compactMap { index, line in
        guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return nil
        }
        let box = line.boundingBox
        return OCRToken(
          id: String(format: "vision-%04d", index + 1),
          text: line.text,
          boundingBox: NormalizedBoundingBox(
            x: Double(box.origin.x),
            y: Double(box.origin.y),
            width: Double(box.width),
            height: Double(box.height)
          ),
          confidence: Double(line.confidence),
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
