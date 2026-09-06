import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import CoreText

  @testable import AppleVisionAdapter

  let goldenSceneRepository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  /// A synthetic scene descriptor decoded from `Fixtures/GoldenScenes/manifest.json`.
  ///
  /// Scenes render deterministically with Core Text at test time, so no binary
  /// images live in the repository. All content must stay fictional.
  struct GoldenScene: Decodable, Sendable {
    struct Canvas: Decodable, Sendable {
      var width: Double
      var height: Double
    }

    struct TextLine: Decodable, Sendable {
      var text: String
      var fontSize: Double
      var x: Double
      var y: Double
    }

    var identifier: String
    var canvas: Canvas
    var backgroundGray: Double?
    var cardQuad: [[Double]]?
    var cardGray: Double?
    var textGray: Double?
    var lines: [TextLine]
    var recognitionLanguages: [String]?
    var automaticallyDetectsLanguage: Bool?
    var cardRegionMode: String?
    var expected: [String: [String]]

    var resolvedBackgroundGray: Double { backgroundGray ?? 1 }
    var resolvedCardGray: Double { cardGray ?? 0.96 }
    var resolvedTextGray: Double { textGray ?? 0 }
    var resolvedRecognitionLanguages: [String] { recognitionLanguages ?? ["en-US"] }
    var resolvedAutomaticallyDetectsLanguage: Bool { automaticallyDetectsLanguage ?? false }
    var resolvedCardRegionIsDisabled: Bool { (cardRegionMode ?? "disabled") == "disabled" }

    var canvasSize: CGSize {
      CGSize(width: canvas.width, height: canvas.height)
    }

    /// Quad corners in normalized top-left-origin order: top-left, top-right, bottom-right, bottom-left.
    var quadPoints: [CGPoint]? {
      guard let cardQuad, cardQuad.count == 4 else { return nil }
      return cardQuad.map { point in
        CGPoint(x: point[0] * canvas.width, y: (1 - point[1]) * canvas.height)
      }
    }

    var scanConfiguration: AppleVisionScanConfiguration {
      let mode: AppleVisionCardRegionConfiguration.Mode =
        resolvedCardRegionIsDisabled ? .disabled : .automatic
      return AppleVisionScanConfiguration(
        recognitionLanguages: resolvedRecognitionLanguages,
        automaticallyDetectsLanguage: resolvedAutomaticallyDetectsLanguage,
        cardRegion: AppleVisionCardRegionConfiguration(mode: mode)
      )
    }
  }

  enum GoldenSceneManifest {
    static func load() throws -> [GoldenScene] {
      let data = try Data(
        contentsOf: goldenSceneRepository.appendingPathComponent(
          "Fixtures/GoldenScenes/manifest.json")
      )
      return try JSONDecoder().decode([GoldenScene].self, from: data)
    }
  }

  enum GoldenSceneRenderer {
    static func render(_ scene: GoldenScene) throws -> CGImage {
      let size = scene.canvasSize
      let context = try requireContext(width: Int(size.width), height: Int(size.height))

      context.setFillColor(CGColor(gray: CGFloat(scene.resolvedBackgroundGray), alpha: 1))
      context.fill(CGRect(origin: .zero, size: size))

      if let points = scene.quadPoints {
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() {
          context.addLine(to: point)
        }
        context.closePath()
        context.setFillColor(CGColor(gray: CGFloat(scene.resolvedCardGray), alpha: 1))
        context.fillPath()
      }

      for line in scene.lines {
        draw(
          line.text,
          at: CGPoint(x: line.x * size.width, y: (1 - line.y) * size.height),
          fontSize: CGFloat(line.fontSize),
          color: CGColor(gray: CGFloat(scene.resolvedTextGray), alpha: 1),
          in: context
        )
      }
      guard let image = context.makeImage() else {
        throw GoldenSceneError.failedToRenderImage
      }
      return image
    }

    private static func requireContext(width: Int, height: Int) throws -> CGContext {
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
      else {
        throw GoldenSceneError.failedToCreateContext
      }
      return context
    }

    private static func draw(
      _ text: String, at point: CGPoint, fontSize: CGFloat, color: CGColor, in context: CGContext
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
      let line = CTLineCreateWithAttributedString(attributed)
      context.textPosition = point
      CTLineDraw(line, context)
    }
  }

  enum GoldenSceneError: Error {
    case failedToCreateContext
    case failedToRenderImage
  }

  /// Deterministic expected-vs-actual comparison for golden scene results.
  ///
  /// Values match when their whitespace-stripped, case-folded forms are equal;
  /// phone fields additionally match on digit-only forms so formatting variance
  /// in provider readings does not mask real regressions.
  enum GoldenFieldComparator {
    private static let phoneFields: Set<String> = [
      CardField.workPhoneNumbers.rawValue,
      CardField.mobilePhoneNumbers.rawValue,
      CardField.faxNumbers.rawValue,
    ]

    static func mismatches(
      expected: [String: [String]],
      result: CardFieldResult
    ) -> [String] {
      var messages: [String] = []
      for field in CardField.allCases {
        let expectedValues = expected[field.rawValue] ?? []
        let actualValues = result.values(for: field).map(\.normalizedValue)
        let unmatchedActual = unmatched(
          actualValues, against: expectedValues, field: field.rawValue)
        let unmatchedExpected = unmatched(
          expectedValues, against: actualValues, field: field.rawValue)

        if !unmatchedActual.isEmpty {
          messages.append("\(field.rawValue) unexpected: \(unmatchedActual.sorted())")
        }
        if !unmatchedExpected.isEmpty {
          messages.append("\(field.rawValue) missing: \(unmatchedExpected.sorted())")
        }
      }
      return messages
    }

    private static func unmatched(
      _ values: [String], against candidates: [String], field: String
    ) -> [String] {
      var remaining = candidates
      return values.filter { value in
        if let index = remaining.firstIndex(where: { matches(value, $0, field: field) }) {
          remaining.remove(at: index)
          return false
        }
        return true
      }
    }

    private static func matches(_ lhs: String, _ rhs: String, field: String) -> Bool {
      if normalized(lhs) == normalized(rhs) {
        return true
      }
      if phoneFields.contains(field) {
        return digits(lhs) == digits(rhs)
      }
      return false
    }

    static func normalized(_ value: String) -> String {
      value.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .lowercased().filter { !$0.isWhitespace }
    }

    static func digits(_ value: String) -> String {
      value.filter(\.isNumber)
    }
  }
#endif
