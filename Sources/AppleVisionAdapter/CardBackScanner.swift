import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import ImageIO
  import Vision

  /// A content-free description of one barcode observed on a card back.
  public struct AppleVisionDetectedBarcode: Equatable, Sendable {
    public enum PayloadKind: String, Codable, Sendable {
      case vCard
      case url
      case unsupported
    }

    public var symbology: String
    public var payloadKind: PayloadKind
    public var boundingBox: NormalizedBoundingBox

    public init(
      symbology: String,
      payloadKind: PayloadKind,
      boundingBox: NormalizedBoundingBox
    ) {
      self.symbology = symbology
      self.payloadKind = payloadKind
      self.boundingBox = boundingBox
    }
  }

  /// Locally recognized text and barcode-derived suggestions from a card back.
  public struct AppleVisionBackScanResult: Equatable, Sendable {
    public var tokens: [OCRToken]
    public var fields: CardFieldResult
    public var detectedBarcodes: [AppleVisionDetectedBarcode]
    public var cardRegionSelection: AppleVisionCardRegionSelection?
    /// Present only when the shared diagnostics option was explicitly enabled.
    public var diagnostics: AppleVisionBackScanDiagnostics?

    public init(
      tokens: [OCRToken],
      fields: CardFieldResult,
      detectedBarcodes: [AppleVisionDetectedBarcode],
      cardRegionSelection: AppleVisionCardRegionSelection?,
      diagnostics: AppleVisionBackScanDiagnostics? = nil
    ) {
      self.tokens = tokens
      self.fields = fields
      self.detectedBarcodes = detectedBarcodes
      self.cardRegionSelection = cardRegionSelection
      self.diagnostics = diagnostics
    }
  }

  /// Scans card-back text plus QR/barcode payloads without persistence or networking.
  public struct CardBackScanner: Sendable {
    public var configuration: AppleVisionScanConfiguration

    private let classifier: CardFieldClassifier
    private let vCardParser: VCardParser

    public init(
      classifier: CardFieldClassifier = CardFieldClassifier(),
      configuration: AppleVisionScanConfiguration = AppleVisionScanConfiguration(),
      vCardParser: VCardParser = VCardParser()
    ) {
      self.classifier = classifier
      self.configuration = configuration
      self.vCardParser = vCardParser
    }

    /// Scans encoded card-back bytes, honoring embedded EXIF orientation by default.
    public func scan(
      imageData: Data,
      orientation: CGImagePropertyOrientation? = nil
    ) throws -> AppleVisionBackScanResult {
      guard
        let source = CGImageSourceCreateWithData(imageData as CFData, nil),
        CGImageSourceGetCount(source) > 0,
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        throw AppleVisionScanError.invalidImageData
      }
      return try scan(
        cgImage: image,
        orientation: orientation ?? Self.orientation(from: source)
      )
    }

    /// Scans a decoded card-back image for text and barcode payloads.
    public func scan(
      cgImage: CGImage,
      orientation: CGImagePropertyOrientation = .up
    ) throws -> AppleVisionBackScanResult {
      let instrumentation = makeInstrumentation()
      let decoded = try measure(.sourceBarcodeDetection, instrumentation: instrumentation) {
        instrumentation?.recordSourceBarcodeRequest()
        return try decodedBarcodes(in: cgImage, orientation: orientation)
      }
      let textResult = try textScan(
        cgImage: cgImage,
        orientation: orientation,
        barcodeRegions: decoded.map(\.metadata.boundingBox),
        instrumentation: instrumentation
      )
      let fields = try measure(.classificationAndMerge, instrumentation: instrumentation) {
        let textFields: CardFieldResult
        do {
          if let tokens = textResult?.tokens, !tokens.isEmpty {
            textFields = try classifier.classify(tokens)
          } else {
            textFields = CardFieldResult()
          }
        } catch {
          throw AppleVisionScanError.classificationFailed(error.localizedDescription)
        }
        let barcodeFields = decoded.reduce(
          CardFieldResult(ruleVersions: ["barcode-1.0.0"])
        ) { current, barcode in
          guard let fields = barcode.fields else { return current }
          return CardScanSession().merge(front: current, back: fields).merged
        }
        return CardScanSession().merge(
          front: textFields,
          back: barcodeFields.allValuesForBackScan.isEmpty ? nil : barcodeFields
        ).merged
      }

      return AppleVisionBackScanResult(
        tokens: textResult?.tokens ?? [],
        fields: fields,
        detectedBarcodes: decoded.map(\.metadata),
        cardRegionSelection: textResult?.cardRegionSelection,
        diagnostics: instrumentation?.snapshot()
      )
    }

    private func makeInstrumentation() -> BackScanInstrumentation? {
      guard configuration.diagnostics.isEnabled else { return nil }
      return BackScanInstrumentation(clock: configuration.diagnostics.clock)
    }

    private func measure<T>(
      _ stage: AppleVisionBackScanStage,
      instrumentation: BackScanInstrumentation?,
      operation: () throws -> T
    ) rethrows -> T {
      guard let instrumentation else { return try operation() }
      return try instrumentation.measure(stage, operation)
    }

    private func textScan(
      cgImage: CGImage,
      orientation: CGImagePropertyOrientation,
      barcodeRegions: [NormalizedBoundingBox],
      instrumentation: BackScanInstrumentation?
    ) throws -> BackTextResult? {
      do {
        var tokenConfiguration = configuration
        tokenConfiguration.diagnostics = .disabled
        let prepared = try measure(.tokenRecognition, instrumentation: instrumentation) {
          try AppleVisionScanner(
            classifier: classifier,
            configuration: tokenConfiguration
          ).scanTokensWithRecognitionImage(cgImage: cgImage, orientation: orientation)
        }
        let recognized = prepared.result
        let maskingRegions: [NormalizedBoundingBox]
        if case .isolated = recognized.cardRegionSelection {
          maskingRegions = try measure(
            .isolatedMaskDetection,
            instrumentation: instrumentation
          ) {
            instrumentation?.recordIsolatedMaskBarcodeRequest()
            return try detectedBarcodeRegions(
              in: prepared.recognitionImage,
              orientation: .up
            )
          }
        } else {
          maskingRegions = barcodeRegions
        }
        let tokens = Self.tokensOutsideBarcodeRegions(
          recognized.tokens,
          barcodeRegions: maskingRegions
        )
        return BackTextResult(
          tokens: tokens,
          cardRegionSelection: recognized.cardRegionSelection
        )
      } catch AppleVisionScanError.noRecognizedText where !barcodeRegions.isEmpty {
        return nil
      }
    }

    /// Prevents QR modules from being interpreted as names or organizations.
    ///
    /// Callers provide barcode boxes detected on the exact upright recognition
    /// image, so full-image and perspective-corrected scans share one coordinate
    /// system without approximating the original card quadrilateral.
    static func tokensOutsideBarcodeRegions(
      _ tokens: [OCRToken],
      barcodeRegions: [NormalizedBoundingBox]
    ) -> [OCRToken] {
      guard !barcodeRegions.isEmpty else { return tokens }

      return tokens.filter { token in
        !barcodeRegions.contains { region in
          overlapRatio(token.boundingBox, inflated: region) >= 0.5
        }
      }
    }

    private static func overlapRatio(
      _ token: NormalizedBoundingBox,
      inflated region: NormalizedBoundingBox
    ) -> Double {
      guard token.area > 0 else { return 0 }
      let padding = 0.015
      let minX = max(token.x, max(region.x - padding, 0))
      let minY = max(token.y, max(region.y - padding, 0))
      let maxX = min(token.x + token.width, min(region.x + region.width + padding, 1))
      let maxY = min(token.y + token.height, min(region.y + region.height + padding, 1))
      let intersection = max(maxX - minX, 0) * max(maxY - minY, 0)
      return intersection / token.area
    }

    private func decodedBarcodes(
      in image: CGImage,
      orientation: CGImagePropertyOrientation
    ) throws -> [DecodedBarcode] {
      try barcodeObservations(in: image, orientation: orientation)
        .sorted(by: Self.barcodeReadingOrder)
        .enumerated()
        .map { offset, observation in
          let payload = observation.payloadStringValue ?? ""
          let fields: CardFieldResult?
          let kind: AppleVisionDetectedBarcode.PayloadKind
          if payload.uppercased().hasPrefix("BEGIN:VCARD") {
            fields = (try? vCardParser.parse(payload))?.rebasingBarcodeSources(offset + 1)
            kind = fields == nil ? .unsupported : .vCard
          } else if Self.isExplicitURL(payload) {
            fields = Self.urlFields(payload, barcodeIndex: offset + 1)
            kind = .url
          } else {
            fields = nil
            kind = .unsupported
          }
          return DecodedBarcode(
            metadata: AppleVisionDetectedBarcode(
              symbology: observation.symbology.rawValue,
              payloadKind: kind,
              boundingBox: Self.normalizedBox(observation.boundingBox)
            ),
            fields: fields
          )
        }
    }

    private func detectedBarcodeRegions(
      in image: CGImage,
      orientation: CGImagePropertyOrientation
    ) throws -> [NormalizedBoundingBox] {
      try barcodeObservations(in: image, orientation: orientation)
        .map { Self.normalizedBox($0.boundingBox) }
    }

    private func barcodeObservations(
      in image: CGImage,
      orientation: CGImagePropertyOrientation
    ) throws -> [VNBarcodeObservation] {
      let request = VNDetectBarcodesRequest()
      let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
      do {
        try handler.perform([request])
      } catch {
        throw AppleVisionScanError.recognitionFailed(error.localizedDescription)
      }
      return request.results ?? []
    }

    private static func normalizedBox(_ box: CGRect) -> NormalizedBoundingBox {
      NormalizedBoundingBox(
        x: box.origin.x,
        y: box.origin.y,
        width: box.width,
        height: box.height
      )
    }

    private static func barcodeReadingOrder(
      _ lhs: VNBarcodeObservation,
      _ rhs: VNBarcodeObservation
    ) -> Bool {
      if lhs.boundingBox.midY != rhs.boundingBox.midY {
        return lhs.boundingBox.midY > rhs.boundingBox.midY
      }
      if lhs.boundingBox.minX != rhs.boundingBox.minX {
        return lhs.boundingBox.minX < rhs.boundingBox.minX
      }
      return lhs.symbology.rawValue < rhs.symbology.rawValue
    }

    private static func isExplicitURL(_ payload: String) -> Bool {
      guard let components = URLComponents(string: payload),
        components.scheme == "http" || components.scheme == "https"
      else { return false }
      return components.host?.contains(".") == true
    }

    private static func urlFields(_ payload: String, barcodeIndex: Int) -> CardFieldResult {
      CardFieldResult(
        ruleVersions: ["barcode-1.0.0"],
        websites: [
          ClassifiedValue(
            normalizedValue: payload,
            originalValue: payload,
            confidence: 0.995,
            evidence: [.syntaxMatch],
            sourceTokenIdentifiers: [
              "barcode:\(String(format: "%04d", barcodeIndex)):url"
            ]
          )
        ],
        overallConfidence: 0.995
      )
    }

    private static func orientation(
      from source: CGImageSource
    ) -> CGImagePropertyOrientation {
      guard
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
          as? [CFString: Any],
        let rawValue = properties[kCGImagePropertyOrientation] as? UInt32,
        let orientation = CGImagePropertyOrientation(rawValue: rawValue)
      else {
        return .up
      }
      return orientation
    }

    private struct DecodedBarcode {
      var metadata: AppleVisionDetectedBarcode
      var fields: CardFieldResult?
    }

    private struct BackTextResult {
      var tokens: [OCRToken]
      var cardRegionSelection: AppleVisionCardRegionSelection
    }
  }

  extension CardFieldResult {
    fileprivate var allValuesForBackScan: [ClassifiedValue] {
      [fullName, preferredName, jobTitle, department, organization].compactMap { $0 }
        + alternateNames + emailAddresses + mobilePhoneNumbers + workPhoneNumbers + faxNumbers
        + websites + professionalProfileURLs + socialHandles + addresses
    }

    fileprivate func rebasingBarcodeSources(_ barcodeIndex: Int) -> CardFieldResult {
      var result = self
      let prefix = "barcode:\(String(format: "%04d", barcodeIndex)):"
      result.fullName = result.fullName.map { $0.rebasingSources(prefix) }
      result.preferredName = result.preferredName.map { $0.rebasingSources(prefix) }
      result.jobTitle = result.jobTitle.map { $0.rebasingSources(prefix) }
      result.department = result.department.map { $0.rebasingSources(prefix) }
      result.organization = result.organization.map { $0.rebasingSources(prefix) }
      result.alternateNames = result.alternateNames.map { $0.rebasingSources(prefix) }
      result.emailAddresses = result.emailAddresses.map { $0.rebasingSources(prefix) }
      result.mobilePhoneNumbers = result.mobilePhoneNumbers.map { $0.rebasingSources(prefix) }
      result.workPhoneNumbers = result.workPhoneNumbers.map { $0.rebasingSources(prefix) }
      result.faxNumbers = result.faxNumbers.map { $0.rebasingSources(prefix) }
      result.websites = result.websites.map { $0.rebasingSources(prefix) }
      result.professionalProfileURLs = result.professionalProfileURLs.map {
        $0.rebasingSources(prefix)
      }
      result.socialHandles = result.socialHandles.map { $0.rebasingSources(prefix) }
      result.addresses = result.addresses.map { $0.rebasingSources(prefix) }
      return result
    }
  }

  extension ClassifiedValue {
    fileprivate func rebasingSources(_ prefix: String) -> ClassifiedValue {
      var value = self
      value.sourceTokenIdentifiers = sourceTokenIdentifiers.map { prefix + $0 }
      value.alternativeCandidates = alternativeCandidates.map { candidate in
        var candidate = candidate
        candidate.sourceTokenIdentifiers = candidate.sourceTokenIdentifiers.map { prefix + $0 }
        return candidate
      }
      return value
    }
  }
#endif
