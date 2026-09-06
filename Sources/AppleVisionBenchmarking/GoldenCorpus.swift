import AppleVisionAdapter
import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(Vision)
  import CoreGraphics
  import CoreImage
  import CoreText

  /// Versioned manifest for deterministic, synthetic business-card scenes.
  public struct GoldenCorpusManifest: Decodable, Sendable {
    public var schemaVersion: Int
    public var corpusVersion: String
    public var profiles: [String: GoldenContentProfile]
    public var layouts: [GoldenLayoutTemplate]

    public init(data: Data) throws {
      self = try JSONDecoder().decode(Self.self, from: data)
      guard schemaVersion == 2 else {
        throw GoldenCorpusError.unsupportedSchemaVersion(schemaVersion)
      }
    }

    /// Expands every layout into exactly two stable capture variants.
    public func expandedCases() throws -> [GoldenSceneCase] {
      var result: [GoldenSceneCase] = []
      for layout in layouts {
        guard let profile = profiles[layout.profile] else {
          throw GoldenCorpusError.missingProfile(layout.profile)
        }
        guard layout.variants.count == 2 else {
          throw GoldenCorpusError.invalidVariantCount(layout.identifier)
        }
        for variant in layout.variants {
          result.append(
            GoldenSceneCase(
              identifier: "\(layout.identifier)-\(variant.identifier)",
              layoutIdentifier: layout.identifier,
              variantIdentifier: variant.identifier,
              corpusVersion: corpusVersion,
              tags: Array(Set(layout.tags + variant.tags)).sorted(),
              canvas: layout.canvas,
              preset: layout.preset,
              backgroundGray: layout.backgroundGray,
              cardGray: layout.cardGray,
              textGray: layout.textGray,
              cardQuad: layout.cardQuad,
              attemptsCardIsolation: layout.attemptsCardIsolation,
              cardRegionMinimumConfidence: layout.cardRegionMinimumConfidence,
              cardRegionPreferredAspectRatio: layout.cardRegionPreferredAspectRatio,
              cardRegionAspectRatioTolerance: layout.cardRegionAspectRatioTolerance,
              usesSaliencyFallback: layout.usesSaliencyFallback,
              targetedReRecognitionConfidenceLimit: layout
                .targetedReRecognitionConfidenceLimit,
              profile: profile,
              variant: variant
            )
          )
        }
      }
      return result
    }
  }

  public struct GoldenContentProfile: Decodable, Sendable {
    public var lines: [String]
    public var recognitionLanguages: [String]
    public var automaticallyDetectsLanguage: Bool
    public var expected: [String: [String]]
  }

  public struct GoldenCanvas: Decodable, Sendable {
    public var width: Double
    public var height: Double

    public var size: CGSize { CGSize(width: width, height: height) }
  }

  public enum GoldenLayoutPreset: String, Decodable, Sendable {
    case left
    case compact
    case twoColumn
    case centered
    case portrait
    case isolated
    case wide
    case staggered
  }

  public struct GoldenLayoutTemplate: Decodable, Sendable {
    public var identifier: String
    public var profile: String
    public var preset: GoldenLayoutPreset
    public var canvas: GoldenCanvas
    public var tags: [String]
    public var backgroundGray: Double
    public var cardGray: Double?
    public var textGray: Double
    public var cardQuad: [[Double]]?
    public var attemptsCardIsolation: Bool?
    public var cardRegionMinimumConfidence: Float?
    public var cardRegionPreferredAspectRatio: Double?
    public var cardRegionAspectRatioTolerance: Double?
    public var usesSaliencyFallback: Bool?
    public var targetedReRecognitionConfidenceLimit: Double?
    public var variants: [GoldenCaptureVariant]
  }

  public struct GoldenCaptureVariant: Decodable, Sendable {
    public var identifier: String
    public var tags: [String]
    public var fontScale: Double?
    public var offsetX: Double?
    public var offsetY: Double?
    public var textGrayDelta: Double?
    public var backgroundGrayDelta: Double?
    public var blurRadius: Double?
    public var exposureEV: Double?
    public var shadowOpacity: Double?
    public var glareOpacity: Double?
    public var contactFontScale: Double?
    public var contactTextGrayDelta: Double?
    public var contactBlurRadius: Double?
    public var contactShadowOpacity: Double?
    public var contactGlareOpacity: Double?
  }

  /// One rendered case. Identifiers are used only by local regression failures;
  /// aggregate benchmark reports never serialize them.
  public struct GoldenSceneCase: Sendable {
    public var identifier: String
    public var layoutIdentifier: String
    public var variantIdentifier: String
    public var corpusVersion: String
    public var tags: [String]
    public var canvas: GoldenCanvas
    public var preset: GoldenLayoutPreset
    public var backgroundGray: Double
    public var cardGray: Double?
    public var textGray: Double
    public var cardQuad: [[Double]]?
    public var attemptsCardIsolation: Bool?
    public var cardRegionMinimumConfidence: Float?
    public var cardRegionPreferredAspectRatio: Double?
    public var cardRegionAspectRatioTolerance: Double?
    public var usesSaliencyFallback: Bool?
    public var targetedReRecognitionConfidenceLimit: Double?
    public var profile: GoldenContentProfile
    public var variant: GoldenCaptureVariant

    public var expected: [String: [String]] { profile.expected }
    public var resolvedCardRegionIsDisabled: Bool {
      !(attemptsCardIsolation ?? (cardQuad != nil))
    }

    public var scanConfiguration: AppleVisionScanConfiguration {
      AppleVisionScanConfiguration(
        recognitionLanguages: profile.recognitionLanguages,
        automaticallyDetectsLanguage: profile.automaticallyDetectsLanguage,
        cardRegion: AppleVisionCardRegionConfiguration(
          mode: resolvedCardRegionIsDisabled ? .disabled : .automatic,
          minimumConfidence: cardRegionMinimumConfidence ?? 0.50,
          preferredAspectRatio: cardRegionPreferredAspectRatio ?? 1.75,
          aspectRatioTolerance: cardRegionAspectRatioTolerance ?? 0.65,
          usesSaliencyFallback: usesSaliencyFallback ?? true
        ),
        targetedReRecognitionConfidenceLimit: targetedReRecognitionConfidenceLimit ?? 0.35
      )
    }
  }

  public enum GoldenCorpusError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case missingProfile(String)
    case invalidVariantCount(String)
    case invalidCardQuad(String)
    case failedToCreateContext
    case failedToRenderImage
  }

  /// Deterministic Core Text/Core Graphics renderer for golden cases.
  public enum GoldenSceneRenderer {
    public static func render(_ scene: GoldenSceneCase) throws -> CGImage {
      let width = Int(scene.canvas.width)
      let height = Int(scene.canvas.height)
      guard
        let context = CGContext(
          data: nil,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { throw GoldenCorpusError.failedToCreateContext }

      let background = clamp(
        scene.backgroundGray + (scene.variant.backgroundGrayDelta ?? 0))
      context.setFillColor(CGColor(gray: background, alpha: 1))
      context.fill(CGRect(origin: .zero, size: scene.canvas.size))

      if scene.tags.contains("complex-background") {
        drawBackgroundGrid(in: context, size: scene.canvas.size)
      }
      if scene.tags.contains("overlapping-card") {
        drawOverlappingCard(in: context, size: scene.canvas.size)
      }
      if let quad = try cardPoints(for: scene) {
        drawCard(quad, gray: clamp(scene.cardGray ?? 0.96), in: context)
      }
      if let shadowOpacity = scene.variant.shadowOpacity, shadowOpacity > 0 {
        drawShadow(opacity: shadowOpacity, in: context, size: scene.canvas.size)
      }
      if let glareOpacity = scene.variant.glareOpacity, glareOpacity > 0 {
        drawGlare(opacity: glareOpacity, in: context, size: scene.canvas.size)
      }

      let frames = lineFrames(preset: scene.preset, count: scene.profile.lines.count)
      let scale = scene.variant.fontScale ?? 1
      let offsetX = scene.variant.offsetX ?? 0
      let offsetY = scene.variant.offsetY ?? 0
      let textGray = clamp(scene.textGray + (scene.variant.textGrayDelta ?? 0))
      let referenceEdge = min(scene.canvas.width, scene.canvas.height)
      let contactStartIndex = max(scene.profile.lines.count - 2, 0)
      for (index, pair) in zip(scene.profile.lines, frames).enumerated() {
        let (text, frame) = pair
        let isContact = index >= contactStartIndex
        draw(
          text,
          at: CGPoint(
            x: (frame.x + offsetX) * scene.canvas.width,
            y: (1 - frame.y - offsetY) * scene.canvas.height
          ),
          fontSize: CGFloat(
            referenceEdge * frame.fontScale * scale
              * (isContact ? (scene.variant.contactFontScale ?? 1) : 1)
          ),
          color: CGColor(
            gray: isContact
              ? clamp(Double(textGray) + (scene.variant.contactTextGrayDelta ?? 0))
              : textGray,
            alpha: 1
          ),
          in: context
        )
      }

      let contactRegion = contactRegion(
        frames: frames,
        contactStartIndex: contactStartIndex,
        canvas: scene.canvas.size
      )
      if let opacity = scene.variant.contactShadowOpacity, opacity > 0 {
        drawContactOverlay(
          gray: 0, opacity: opacity, region: contactRegion, in: context)
      }
      if let opacity = scene.variant.contactGlareOpacity, opacity > 0 {
        drawContactOverlay(
          gray: 1, opacity: opacity, region: contactRegion, in: context)
      }

      if scene.tags.contains("qr") {
        drawSyntheticQR(in: context, size: scene.canvas.size)
      }
      guard var image = context.makeImage() else {
        throw GoldenCorpusError.failedToRenderImage
      }
      if (scene.variant.blurRadius ?? 0) > 0 || (scene.variant.exposureEV ?? 0) != 0
        || (scene.variant.contactBlurRadius ?? 0) > 0
      {
        image = filtered(image, variant: scene.variant, contactRegion: contactRegion) ?? image
      }
      return image
    }

    private struct LineFrame {
      var x: Double
      var y: Double
      var fontScale: Double
    }

    private static func lineFrames(preset: GoldenLayoutPreset, count: Int) -> [LineFrame] {
      let frames: [LineFrame]
      switch preset {
      case .left:
        frames = framesAt(x: 0.08, ys: [0.25, 0.38, 0.51, 0.63, 0.75])
      case .compact:
        frames = framesAt(x: 0.10, ys: [0.22, 0.36, 0.51, 0.65, 0.78], scale: 0.052)
      case .twoColumn:
        frames = [
          LineFrame(x: 0.07, y: 0.26, fontScale: 0.071),
          LineFrame(x: 0.07, y: 0.42, fontScale: 0.048),
          LineFrame(x: 0.07, y: 0.58, fontScale: 0.052),
          LineFrame(x: 0.53, y: 0.50, fontScale: 0.040),
          LineFrame(x: 0.53, y: 0.66, fontScale: 0.040),
        ]
      case .centered:
        frames = framesAt(x: 0.27, ys: [0.22, 0.36, 0.50, 0.64, 0.77])
      case .portrait:
        frames = framesAt(x: 0.10, ys: [0.20, 0.31, 0.43, 0.55, 0.67])
      case .isolated:
        frames = framesAt(x: 0.26, ys: [0.27, 0.37, 0.47, 0.57, 0.66], scale: 0.052)
      case .wide:
        frames = framesAt(x: 0.05, ys: [0.25, 0.39, 0.53, 0.66, 0.78])
      case .staggered:
        frames = [
          LineFrame(x: 0.08, y: 0.23, fontScale: 0.071),
          LineFrame(x: 0.18, y: 0.37, fontScale: 0.048),
          LineFrame(x: 0.10, y: 0.51, fontScale: 0.044),
          LineFrame(x: 0.22, y: 0.65, fontScale: 0.042),
          LineFrame(x: 0.12, y: 0.78, fontScale: 0.040),
        ]
      }
      if count <= frames.count { return Array(frames.prefix(count)) }
      return frames + Array(repeating: frames.last!, count: count - frames.count)
    }

    private static func framesAt(
      x: Double, ys: [Double], scale: Double = 0.045
    ) -> [LineFrame] {
      ys.enumerated().map { index, y in
        LineFrame(x: x, y: y, fontScale: index == 0 ? 0.071 : scale)
      }
    }

    private static func cardPoints(for scene: GoldenSceneCase) throws -> [CGPoint]? {
      guard let quad = scene.cardQuad else { return nil }
      guard quad.count == 4, quad.allSatisfy({ $0.count == 2 }) else {
        throw GoldenCorpusError.invalidCardQuad(scene.layoutIdentifier)
      }
      return quad.map { point in
        CGPoint(x: point[0] * scene.canvas.width, y: (1 - point[1]) * scene.canvas.height)
      }
    }

    private static func drawCard(_ points: [CGPoint], gray: CGFloat, in context: CGContext) {
      context.beginPath()
      context.move(to: points[0])
      for point in points.dropFirst() { context.addLine(to: point) }
      context.closePath()
      context.setFillColor(CGColor(gray: gray, alpha: 1))
      context.fillPath()
    }

    private static func draw(
      _ text: String,
      at point: CGPoint,
      fontSize: CGFloat,
      color: CGColor,
      in context: CGContext
    ) {
      let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
      let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
      ]
      guard
        let attributed = CFAttributedStringCreate(
          nil, text as CFString, attributes as CFDictionary
        )
      else { return }
      context.textPosition = point
      CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }

    private static func drawBackgroundGrid(in context: CGContext, size: CGSize) {
      context.setStrokeColor(CGColor(gray: 0.72, alpha: 0.35))
      context.setLineWidth(2)
      for offset in stride(from: 0, through: Int(size.width), by: 90) {
        context.move(to: CGPoint(x: offset, y: 0))
        context.addLine(to: CGPoint(x: offset, y: Int(size.height)))
      }
      for offset in stride(from: 0, through: Int(size.height), by: 90) {
        context.move(to: CGPoint(x: 0, y: offset))
        context.addLine(to: CGPoint(x: Int(size.width), y: offset))
      }
      context.strokePath()
    }

    private static func drawOverlappingCard(in context: CGContext, size: CGSize) {
      context.saveGState()
      context.translateBy(x: size.width * 0.18, y: size.height * 0.13)
      context.rotate(by: -0.08)
      context.setFillColor(CGColor(gray: 0.75, alpha: 1))
      context.fill(
        CGRect(x: 0, y: 0, width: size.width * 0.66, height: size.height * 0.52))
      context.restoreGState()
    }

    private static func drawSyntheticQR(in context: CGContext, size: CGSize) {
      let cell = max(min(size.width, size.height) * 0.012, 5)
      let origin = CGPoint(x: size.width * 0.82, y: size.height * 0.12)
      context.setFillColor(CGColor(gray: 0.1, alpha: 1))
      for row in 0..<9 {
        for column in 0..<9 where (row * 3 + column * 5 + row * column) % 4 < 2 {
          context.fill(
            CGRect(
              x: origin.x + CGFloat(column) * cell,
              y: origin.y + CGFloat(row) * cell,
              width: cell,
              height: cell
            ))
        }
      }
    }

    private static func drawShadow(opacity: Double, in context: CGContext, size: CGSize) {
      context.setFillColor(CGColor(gray: 0, alpha: clamp(opacity)))
      let points = [
        CGPoint(x: 0, y: 0), CGPoint(x: size.width * 0.58, y: 0),
        CGPoint(x: size.width * 0.35, y: size.height), CGPoint(x: 0, y: size.height),
      ]
      context.beginPath()
      context.move(to: points[0])
      for point in points.dropFirst() { context.addLine(to: point) }
      context.closePath()
      context.fillPath()
    }

    private static func drawGlare(opacity: Double, in context: CGContext, size: CGSize) {
      context.setFillColor(CGColor(gray: 1, alpha: clamp(opacity)))
      context.saveGState()
      context.translateBy(x: size.width * 0.62, y: -size.height * 0.1)
      context.rotate(by: 0.22)
      context.fill(
        CGRect(x: 0, y: 0, width: size.width * 0.14, height: size.height * 1.3))
      context.restoreGState()
    }

    private static func contactRegion(
      frames: [LineFrame],
      contactStartIndex: Int,
      canvas: CGSize
    ) -> CGRect {
      let contacts = Array(frames.dropFirst(contactStartIndex))
      let minimumX = contacts.map(\.x).min() ?? 0
      let minimumY = contacts.map(\.y).min() ?? 0
      let maximumY = contacts.map(\.y).max() ?? 1
      return CGRect(
        x: max((minimumX - 0.025) * canvas.width, 0),
        y: max((1 - maximumY - 0.075) * canvas.height, 0),
        width: min(canvas.width * 0.88, canvas.width),
        height: min((maximumY - minimumY + 0.15) * canvas.height, canvas.height)
      ).intersection(CGRect(origin: .zero, size: canvas))
    }

    private static func drawContactOverlay(
      gray: CGFloat,
      opacity: Double,
      region: CGRect,
      in context: CGContext
    ) {
      context.setFillColor(CGColor(gray: gray, alpha: clamp(opacity)))
      context.fill(region)
    }

    private static func filtered(
      _ image: CGImage,
      variant: GoldenCaptureVariant,
      contactRegion: CGRect
    ) -> CGImage? {
      var output = CIImage(cgImage: image)
      let originalExtent = output.extent
      if let blurRadius = variant.blurRadius, blurRadius > 0 {
        output = output.clampedToExtent().applyingGaussianBlur(sigma: blurRadius)
          .cropped(to: originalExtent)
      }
      if let exposureEV = variant.exposureEV, exposureEV != 0 {
        output = output.applyingFilter(
          "CIExposureAdjust", parameters: [kCIInputEVKey: exposureEV])
      }
      if let radius = variant.contactBlurRadius, radius > 0, !contactRegion.isEmpty {
        let blurred = output.cropped(to: contactRegion).clampedToExtent()
          .applyingGaussianBlur(sigma: radius)
          .cropped(to: contactRegion)
        output = blurred.composited(over: output)
      }
      return CIContext().createCGImage(output, from: originalExtent)
    }

    private static func clamp(_ value: Double) -> CGFloat {
      CGFloat(min(max(value, 0), 1))
    }
  }

  /// Expected-field comparator used by regression tests and aggregate reports.
  public enum GoldenFieldComparison {
    private static let phoneFields: Set<String> = [
      CardField.workPhoneNumbers.rawValue,
      CardField.mobilePhoneNumbers.rawValue,
      CardField.faxNumbers.rawValue,
    ]

    public static func mismatchedFields(
      expected: [String: [String]], result: CardFieldResult
    ) -> [String] {
      CardField.allCases.compactMap { field in
        let expectedValues = expected[field.rawValue] ?? []
        let actualValues = result.values(for: field).map(\.normalizedValue)
        return equivalent(actualValues, expectedValues, field: field.rawValue)
          ? nil : field.rawValue
      }.sorted()
    }

    private static func equivalent(
      _ lhs: [String], _ rhs: [String], field: String
    ) -> Bool {
      var remaining = rhs
      for value in lhs {
        guard
          let index = remaining.firstIndex(where: { matches(value, $0, field: field) })
        else { return false }
        remaining.remove(at: index)
      }
      return remaining.isEmpty
    }

    private static func matches(_ lhs: String, _ rhs: String, field: String) -> Bool {
      if normalized(lhs) == normalized(rhs) { return true }
      if phoneFields.contains(field) { return digits(lhs) == digits(rhs) }
      return false
    }

    private static func normalized(_ value: String) -> String {
      value.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      ).lowercased().filter { !$0.isWhitespace }
    }

    private static func digits(_ value: String) -> String {
      value.filter(\.isNumber)
    }
  }
#endif
