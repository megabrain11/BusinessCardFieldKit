import Foundation

/// The dominant writing script detected in a token.
public enum TokenScript: String, Codable, CaseIterable, Sendable {
  case hangul
  case latin
  case kana
  case han
  case cyrillic
}

/// Deterministic, provider-neutral script detection used to label tokens with a
/// best-effort BCP 47 primary language when the OCR provider does not expose one.
///
/// The inference is intentionally coarse: it identifies scripts, not locales, and
/// never affects classification semantics. It exists so hosts and adapters can
/// populate `OCRToken.language` without provider support or locale-global state.
public enum TokenLanguageInference {
  /// The dominant script of `text`, or `nil` for text without detectable letters.
  ///
  /// Priority resolves mixed-script text: Kana implies Japanese over Han,
  /// Hangul implies Korean, then Han, Cyrillic, and finally Latin.
  public static func dominantScript(of text: String) -> TokenScript? {
    var counts: [TokenScript: Int] = [:]
    for scalar in text.unicodeScalars {
      if let script = script(of: scalar) {
        counts[script, default: 0] += 1
      }
    }
    guard !counts.isEmpty else { return nil }
    for priority in [TokenScript.kana, .hangul, .han, .cyrillic, .latin] {
      if counts[priority] != nil { return priority }
    }
    return nil
  }

  /// A best-effort BCP 47 primary tag for `text`, or `nil` when no script matches.
  public static func inferLanguage(of text: String) -> String? {
    switch dominantScript(of: text) {
    case .hangul: "ko"
    case .kana: "ja"
    case .han: "zh"
    case .cyrillic: "ru"
    case .latin: "en"
    case nil: nil
    }
  }

  /// Applies per-token language labels in place.
  ///
  /// An explicit host hint overwrites every token, matching provider behavior
  /// where one hint describes the whole region. Without a hint, tokens without
  /// a language receive script-based inference; labeled tokens keep theirs.
  public static func apply(to tokens: inout [OCRToken], hint: String?) {
    guard let hint else {
      for index in tokens.indices where tokens[index].language == nil {
        tokens[index].language = inferLanguage(of: tokens[index].text)
      }
      return
    }
    for index in tokens.indices {
      tokens[index].language = hint
    }
  }

  private static func script(of scalar: Unicode.Scalar) -> TokenScript? {
    switch scalar.value {
    case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97C, 0xAC00...0xD7A3:
      return .hangul
    case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF:
      return .kana
    case 0x2E80...0x2EFF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
      return .han
    case 0x0400...0x04FF:
      return .cyrillic
    case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
      return .latin
    default:
      return nil
    }
  }
}
