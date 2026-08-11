import Foundation

public enum OCRNormalizer {
  public static func normalize(_ observations: [OCRToken]) -> [OCRToken] {
    observations.enumerated().compactMap { index, observation in
      let text = observation.text
        .replacingOccurrences(of: "\u{200B}", with: "")
        .precomposedStringWithCanonicalMapping
        .split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      var token = observation
      token.id = observation.id.isEmpty ? String(format: "token-%04d", index + 1) : observation.id
      token.text = text
      token.confidence = min(max(observation.confidence, 0), 1)
      return token
    }
    .sorted(by: readingOrder)
  }

  private static func readingOrder(_ lhs: OCRToken, _ rhs: OCRToken) -> Bool {
    let rowTolerance = max(0.025, min(lhs.boundingBox.height, rhs.boundingBox.height) * 0.5)
    if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) <= rowTolerance {
      if lhs.boundingBox.x != rhs.boundingBox.x { return lhs.boundingBox.x < rhs.boundingBox.x }
      return lhs.id < rhs.id
    }
    if lhs.boundingBox.midY != rhs.boundingBox.midY {
      return lhs.boundingBox.midY > rhs.boundingBox.midY
    }
    return lhs.id < rhs.id
  }
}

extension String {
  var cardFieldFolded: String {
    folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .lowercased()
  }

  var cardFieldIdentityKey: String {
    cardFieldFolded.filter { $0.isLetter || $0.isNumber }
  }
}
