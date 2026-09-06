import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics

  /// Experimental policy controlling whether an otherwise configured dual pass may be skipped.
  public struct AppleVisionConditionalDualPassOptions: Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
      case disabled
      case enabled
    }

    public var mode: Mode
    public var minimumLineConfidence: Double
    public var contentEdgeMargin: Double

    public init(
      mode: Mode = .disabled,
      minimumLineConfidence: Double = 0.82,
      contentEdgeMargin: Double = 0.01
    ) {
      self.mode = mode
      self.minimumLineConfidence = min(max(minimumLineConfidence, 0), 1)
      self.contentEdgeMargin = min(max(contentEdgeMargin, 0), 0.1)
    }
  }

  /// Fixed, content-free outcomes explaining an experimental dual-pass decision.
  public enum AppleVisionDualPassDecisionReason: String, Codable, CaseIterable, Sendable {
    case policyDisabled
    case dualPassUnavailable
    case fullImageFallback
    case targetedRecognition
    case croppedContent
    case lowConfidence
    case multilingualEvidence
    case complexLayout
    case countryCodeConflict
    case ambiguousAlternatives
    case reviewRecommended
    case insufficientStrictContact
    case eligible
  }

  enum DualPassRecognitionContext: Sendable {
    case cardRegionDisabled
    case isolatedCard
    case fullImageFallback
  }

  enum ConditionalDualPassEvaluator {
    private enum StrictFamily: String, Hashable {
      case email
      case website
      case phone
    }

    private struct StrictReading: Hashable {
      var family: StrictFamily
      var normalized: String
      var hasCountryPrefix: Bool
    }

    private static let emailPattern = try! NSRegularExpression(
      pattern: #"[A-Z0-9._%+\-]+\s*@\s*[A-Z0-9.\-]+\.[A-Z]{2,}"#,
      options: [.caseInsensitive]
    )
    private static let websitePattern = try! NSRegularExpression(
      pattern:
        #"(?:https?://|www\.)[A-Z0-9.\-]+\.[A-Z]{2,}(?:/[A-Z0-9._~:/?#\[\]@!$&'()*+,;=%\-]*)?"#,
      options: [.caseInsensitive]
    )
    private static let labeledPhonePattern = try! NSRegularExpression(
      pattern:
        #"(?:MOBILE|MOB|CELL|TEL|PHONE|WORK|OFFICE|FAX|T|M|C|O|P)\s*[:|.]?\s*(\+?[0-9][0-9() .\-]{6,}[0-9])"#,
      options: [.caseInsensitive]
    )

    static func decision(
      lines: [RecognizedLine],
      context: DualPassRecognitionContext,
      requestRole: RecognitionRequestRole,
      options: AppleVisionConditionalDualPassOptions
    ) -> AppleVisionDualPassDecisionReason {
      guard requestRole == .standard else { return .targetedRecognition }
      guard context != .fullImageFallback else { return .fullImageFallback }
      guard !touchesContentEdge(lines, margin: options.contentEdgeMargin) else {
        return .croppedContent
      }
      guard lines.allSatisfy({ Double($0.confidence) >= options.minimumLineConfidence }) else {
        return .lowConfidence
      }
      guard !containsNonLatinScript(lines) else { return .multilingualEvidence }
      guard !hasComplexLayout(lines) else { return .complexLayout }

      let primaryReadings = Set(lines.flatMap { strictReadings(in: $0.text) })
      let alternativeReadings = Set(
        lines.flatMap { line in
          line.alternatives.flatMap { strictReadings(in: $0) }
        })
      let primaryPhones = primaryReadings.filter { $0.family == .phone }
      let alternativePhones = alternativeReadings.filter { $0.family == .phone }
      if hasCountryCodeConflict(primary: primaryPhones, alternatives: alternativePhones) {
        return .countryCodeConflict
      }
      if !alternativeReadings.subtracting(primaryReadings).isEmpty {
        return .ambiguousAlternatives
      }
      guard Set(primaryReadings.map(\.family)).count >= 2 else {
        return .insufficientStrictContact
      }
      let tokens = AppleVisionAdapter.tokens(from: lines, infersLanguages: true)
      if let fields = try? CardFieldClassifier().classify(tokens),
        fields.warnings.contains(.reviewRecommended)
          || fields.warnings.contains(.ambiguousPhoneNumber)
      {
        return .reviewRecommended
      }
      return .eligible
    }

    private static func strictReadings(in text: String) -> [StrictReading] {
      let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
      var values: [StrictReading] = []
      for match in emailPattern.matches(in: text, range: fullRange) {
        guard let range = Range(match.range, in: text) else { continue }
        let normalized = text[range].filter { !$0.isWhitespace }.lowercased()
        values.append(
          StrictReading(family: .email, normalized: normalized, hasCountryPrefix: false))
      }
      for match in websitePattern.matches(in: text, range: fullRange) {
        guard let range = Range(match.range, in: text) else { continue }
        values.append(
          StrictReading(
            family: .website,
            normalized: text[range].lowercased(),
            hasCountryPrefix: false
          ))
      }
      for match in labeledPhonePattern.matches(in: text, range: fullRange) {
        guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else {
          continue
        }
        let raw = String(text[range])
        let digits = raw.filter(\.isNumber)
        guard (7...15).contains(digits.count) else { continue }
        values.append(
          StrictReading(
            family: .phone,
            normalized: digits,
            hasCountryPrefix: raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
          ))
      }
      return Array(Set(values)).sorted {
        if $0.family.rawValue != $1.family.rawValue {
          return $0.family.rawValue < $1.family.rawValue
        }
        return $0.normalized < $1.normalized
      }
    }

    private static func hasCountryCodeConflict(
      primary: Set<StrictReading>, alternatives: Set<StrictReading>
    ) -> Bool {
      for lhs in primary {
        for rhs in alternatives where lhs.hasCountryPrefix != rhs.hasCountryPrefix {
          let suffixLength = min(7, min(lhs.normalized.count, rhs.normalized.count))
          guard suffixLength > 0 else { continue }
          if lhs.normalized.suffix(suffixLength) == rhs.normalized.suffix(suffixLength) {
            return true
          }
        }
      }
      return false
    }

    private static func touchesContentEdge(_ lines: [RecognizedLine], margin: Double) -> Bool {
      guard !lines.isEmpty else { return true }
      return lines.contains { line in
        let box = line.boundingBox
        return !box.origin.x.isFinite || !box.origin.y.isFinite || !box.width.isFinite
          || !box.height.isFinite || box.width <= 0 || box.height <= 0
          || Double(box.minX) <= margin || Double(box.minY) <= margin
          || Double(box.maxX) >= 1 - margin || Double(box.maxY) >= 1 - margin
      }
    }

    private static func containsNonLatinScript(_ lines: [RecognizedLine]) -> Bool {
      lines.contains { line in
        line.text.unicodeScalars.contains { scalar in
          switch scalar.value {
          case 0x0400...0x052F, 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF:
            return true
          default:
            return false
          }
        }
      }
    }

    private static func hasComplexLayout(_ lines: [RecognizedLine]) -> Bool {
      let tokens = lines.enumerated().map { index, line in
        OCRToken(
          id: String(format: "eligibility-%04d", index),
          text: line.text,
          boundingBox: NormalizedBoundingBox(
            x: Double(line.boundingBox.minX),
            y: Double(line.boundingBox.minY),
            width: Double(line.boundingBox.width),
            height: Double(line.boundingBox.height)
          ),
          confidence: Double(line.confidence)
        )
      }
      return LayoutAnalyzer.rows(in: tokens).contains {
        LayoutAnalyzer.columns(in: $0).count > 1
      }
    }
  }
#endif
