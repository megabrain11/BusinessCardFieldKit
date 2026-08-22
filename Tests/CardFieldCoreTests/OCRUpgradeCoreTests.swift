import CardFieldCore
import Foundation
import Testing

private func token(
  _ text: String,
  id: String = "",
  x: Double = 0.1,
  y: Double,
  width: Double = 0.4,
  height: Double = 0.05,
  confidence: Double = 0.96,
  language: String? = nil,
  alternatives: [String] = []
) -> OCRToken {
  OCRToken(
    id: id,
    text: text,
    boundingBox: .init(x: x, y: y, width: width, height: height),
    confidence: confidence,
    language: language,
    alternatives: alternatives
  )
}

@Test("Script inference labels Hangul, Kana, Han, Cyrillic, and Latin text")
func scriptInference() {
  #expect(TokenLanguageInference.inferLanguage(of: "김민서 대표이사") == "ko")
  #expect(TokenLanguageInference.inferLanguage(of: "Alex Kim") == "en")
  #expect(TokenLanguageInference.inferLanguage(of: "こんにちは") == "ja")
  #expect(TokenLanguageInference.inferLanguage(of: "東京都") == "zh")
  #expect(TokenLanguageInference.inferLanguage(of: "Москва") == "ru")
  #expect(TokenLanguageInference.inferLanguage(of: "010-5550-1200") == nil)
  #expect(TokenLanguageInference.inferLanguage(of: "") == nil)
}

@Test("Mixed-script text resolves by priority without losing CJK to Latin")
func mixedScriptPriority() {
  #expect(TokenLanguageInference.dominantScript(of: "김민서 Alex") == .hangul)
  #expect(TokenLanguageInference.dominantScript(of: "東京駅 Tokyo") == .han)
  #expect(TokenLanguageInference.dominantScript(of: "カナダ Canada") == .kana)
}

@Test("Explicit hints win over inference and existing languages are preserved")
func hintPrecedence() {
  var hinted = [
    token("김민서", y: 0.8, language: "fr"),
    token("Alex Kim", y: 0.6),
  ]
  TokenLanguageInference.apply(to: &hinted, hint: "ko")
  #expect(hinted.map(\.language) == ["ko", "ko"])

  var unhinted = [token("김민서", y: 0.8), token("Alex Kim", y: 0.6)]
  TokenLanguageInference.apply(to: &unhinted, hint: nil)
  #expect(unhinted[0].language == "ko")
  #expect(unhinted[1].language == "en")
}

@Test("Legacy encoded tokens without alternatives still decode")
func legacyTokenDecoding() throws {
  let legacyJSON = """
    {
      "id": "vision-0001",
      "text": "Alex Kim",
      "boundingBox": {"x": 0.1, "y": 0.75, "width": 0.35, "height": 0.08},
      "confidence": 0.97
    }
    """
  let decoded = try JSONDecoder().decode(OCRToken.self, from: Data(legacyJSON.utf8))
  #expect(decoded.alternatives.isEmpty)
  #expect(decoded.text == "Alex Kim")

  let modern = OCRToken(
    text: "alex@examp1e.net",
    boundingBox: .init(x: 0.1, y: 0.3, width: 0.5, height: 0.05),
    confidence: 0.9,
    alternatives: ["alex@example.net"]
  )
  let roundTripped = try JSONDecoder().decode(OCRToken.self, from: JSONEncoder().encode(modern))
  #expect(roundTripped.alternatives == ["alex@example.net"])
}

@Test("Layout rows group vertically overlapping tokens top-to-bottom")
func rowGrouping() {
  let rows = LayoutAnalyzer.rows(in: [
    token("email@example.com", id: "c", x: 0.55, y: 0.20, width: 0.35, height: 0.04),
    token("+1 202 555 0147", id: "d", x: 0.10, y: 0.19, width: 0.30, height: 0.06),
    token("ALEX KIM", id: "a", x: 0.10, y: 0.80, width: 0.30, height: 0.08),
    token("Founder", id: "b", x: 0.10, y: 0.70, width: 0.20, height: 0.05),
  ])

  #expect(rows.count == 3)
  #expect(rows[0].tokens.map(\.id) == ["a"])
  #expect(rows[1].tokens.map(\.id) == ["b"])
  #expect(rows[2].tokens.map(\.id) == ["d", "c"])
  #expect(rows[2].boundingBox.width > 0.7)
}

@Test("Columns split a row only on wide horizontal gaps")
func columnSplitting() {
  // Same visual row with a wide gutter between name and phone columns.
  let twoColumnRow = LayoutAnalyzer.rows(in: [
    token("김민서", id: "n", x: 0.08, y: 0.70, width: 0.20, height: 0.07),
    token("02-555-1100", id: "p", x: 0.62, y: 0.69, width: 0.25, height: 0.05),
  ])
  #expect(twoColumnRow.count == 1)
  #expect(
    LayoutAnalyzer.columns(in: twoColumnRow[0]).map { $0.map(\.id) } == [["n"], ["p"]]
  )

  // A narrow gutter keeps one column run.
  let tightRow = LayoutAnalyzer.rows(in: [
    token("김민서", id: "n", x: 0.08, y: 0.70, width: 0.20, height: 0.07),
    token("대표이사", id: "t", x: 0.31, y: 0.69, width: 0.16, height: 0.04),
  ])
  #expect(tightRow.count == 1)
  #expect(LayoutAnalyzer.columns(in: tightRow[0]).count == 1)
}

@Test("Row grouping is deterministic for shuffled input")
func rowDeterminism() {
  let tokens = [
    token("A", id: "1", x: 0.1, y: 0.8),
    token("B", id: "2", x: 0.6, y: 0.79),
    token("C", id: "3", x: 0.2, y: 0.4),
    token("D", id: "4", x: 0.7, y: 0.41),
  ]
  let forward = LayoutAnalyzer.rows(in: tokens).flatMap { $0.tokens.map(\.id) }
  let reversed = LayoutAnalyzer.rows(in: tokens.reversed()).flatMap { $0.tokens.map(\.id) }
  #expect(forward == reversed)
  #expect(forward == ["1", "2", "3", "4"])
}
