import Foundation
import Testing

@testable import CardFieldCore

@Test("vCard 3.0 maps supported contact fields without inventing values")
func vCardThreeFieldMapping() throws {
  let payload = """
    BEGIN:VCARD
    VERSION:3.0
    N:Kim;Alex;;;
    FN:Alex Kim
    ORG:Example Labs;Research
    TITLE:Director
    TEL;TYPE=CELL:+1-202-555-0101
    TEL;TYPE=WORK:+1-202-555-0102
    TEL;TYPE=FAX:+1-202-555-0103
    EMAIL;TYPE=WORK:alex.kim@example.com
    ADR;TYPE=WORK:;;100 Example Road;Sample City;CA;00000;US
    URL:https://example.com/alex
    NOTE:This must not become a classified field
    END:VCARD
    """

  let result = try VCardParser().parse(payload)

  #expect(result.fullName?.normalizedValue == "Alex Kim")
  #expect(result.organization?.normalizedValue == "Example Labs Research")
  #expect(result.jobTitle?.normalizedValue == "Director")
  #expect(result.mobilePhoneNumbers.map(\.normalizedValue) == ["+1-202-555-0101"])
  #expect(result.workPhoneNumbers.map(\.normalizedValue) == ["+1-202-555-0102"])
  #expect(result.faxNumbers.map(\.normalizedValue) == ["+1-202-555-0103"])
  #expect(result.emailAddresses.map(\.normalizedValue) == ["alex.kim@example.com"])
  #expect(result.websites.map(\.normalizedValue) == ["https://example.com/alex"])
  #expect(
    result.addresses.map(\.normalizedValue) == ["100 Example Road, Sample City, CA, 00000, US"])
  #expect(result.unclassifiedLines.isEmpty)
  #expect(result.ruleVersions == ["vcard-1.0.0"])
}

@Test("vCard 4.0 unfolds lines, decodes escapes, and falls back to N")
func vCardFourUnfoldingAndEscapes() throws {
  let payload = """
    BEGIN:VCARD
    VERSION:4.0
    N:Hong;Gildong;;;
    ORG:Example\\, Korea;Research\\;Unit
    TITLE:CEO
    EMAIL:gildong@
     example.org
    ADR:;;1 Example-ro;Seoul;;;Korea
    END:VCARD
    """

  let result = try VCardParser().parse(payload)

  #expect(result.fullName?.normalizedValue == "Gildong Hong")
  #expect(result.organization?.normalizedValue == "Example, Korea Research;Unit")
  #expect(result.emailAddresses.map(\.normalizedValue) == ["gildong@example.org"])
  #expect(result.addresses.map(\.normalizedValue) == ["1 Example-ro, Seoul, Korea"])
}

@Test("Quoted-printable UTF-8 and EUC-KR data produce the same Korean vCard")
func vCardKoreanEncoding() throws {
  let quotedPrintable = """
    BEGIN:VCARD
    VERSION:3.0
    FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=ED=99=8D=EA=B8=B8=EB=8F=99
    EMAIL:gildong@example.net
    END:VCARD
    """
  let utf8 = try VCardParser().parse(quotedPrintable)
  #expect(utf8.fullName?.normalizedValue == "홍길동")

  let eucKR = String.Encoding(rawValue: 0x8000_0940)
  let plain = """
    BEGIN:VCARD
    VERSION:3.0
    FN:홍길동
    EMAIL:gildong@example.net
    END:VCARD
    """
  let data = try #require(plain.data(using: eucKR))
  let decoded = try VCardParser().parse(data)
  #expect(decoded.fullName?.normalizedValue == "홍길동")
  #expect(decoded.emailAddresses.map(\.normalizedValue) == ["gildong@example.net"])

  let encodedName = try #require("홍길동".data(using: eucKR))
    .map { String(format: "=%02X", $0) }
    .joined()
  let quotedEUC = """
    BEGIN:VCARD
    VERSION:3.0
    FN;CHARSET=EUC-KR;ENCODING=QUOTED-PRINTABLE:\(encodedName)
    EMAIL:gildong@example.net
    END:VCARD
    """
  let quotedDecoded = try VCardParser().parse(quotedEUC)
  #expect(quotedDecoded.fullName?.normalizedValue == "홍길동")
}

@Test("Malformed, unsupported, and empty vCards fail closed")
func invalidVCardsFailClosed() {
  #expect(throws: VCardParsingError.invalidEnvelope) {
    try VCardParser().parse("FN:Alex Kim")
  }
  #expect(throws: VCardParsingError.unsupportedVersion) {
    try VCardParser().parse("BEGIN:VCARD\nVERSION:2.1\nFN:Alex Kim\nEND:VCARD")
  }
  #expect(throws: VCardParsingError.noSupportedFields) {
    try VCardParser().parse("BEGIN:VCARD\nVERSION:3.0\nNOTE:Nothing\nEND:VCARD")
  }
}

@Test("Front and back merge deduplicates contacts and prefers barcode evidence")
func frontBackMergeDeduplicatesAndPrefersBarcode() throws {
  let front = CardFieldResult(
    ruleVersions: ["base-1.1.0"],
    fullName: field("Alex Kim", confidence: 0.91, source: "front:name"),
    emailAddresses: [field("alex.kim@example.com", confidence: 0.91, source: "front:email")],
    mobilePhoneNumbers: [field("+1 (202) 555-0101", confidence: 0.90, source: "front:phone")]
  )
  let back = try VCardParser().parse(
    """
    BEGIN:VCARD
    VERSION:3.0
    FN:Alex Kim
    EMAIL:alex.kim@example.com
    TEL;TYPE=CELL:+1-202-555-0101
    URL:https://example.com
    END:VCARD
    """
  )

  let merged = CardScanSession().merge(front: front, back: back)

  #expect(merged.front == front)
  #expect(merged.back == back)
  #expect(merged.merged.emailAddresses.count == 1)
  #expect(merged.merged.mobilePhoneNumbers.count == 1)
  #expect(merged.merged.emailAddresses[0].sourceTokenIdentifiers[0].hasPrefix("vcard:"))
  #expect(merged.merged.mobilePhoneNumbers[0].sourceTokenIdentifiers[0].hasPrefix("vcard:"))
  #expect(merged.merged.websites.map(\.normalizedValue) == ["https://example.com"])
  #expect(!merged.merged.warnings.contains(.reviewRecommended))
}

@Test("A barcode phone subtype replaces an OCR subtype without duplicating the number")
func barcodePhoneSubtypeWinsAcrossFamilies() throws {
  let front = CardFieldResult(
    workPhoneNumbers: [field("202-555-0101", confidence: 0.98, source: "front:phone")]
  )
  let back = try VCardParser().parse(
    "BEGIN:VCARD\nVERSION:3.0\nFN:Alex Kim\nTEL;TYPE=CELL:202-555-0101\nEND:VCARD"
  )

  let result = CardScanSession().merge(front: front, back: back).merged

  #expect(result.mobilePhoneNumbers.map(\.normalizedValue) == ["202-555-0101"])
  #expect(result.workPhoneNumbers.isEmpty)
  #expect(result.faxNumbers.isEmpty)
}

@Test("Conflicting singular barcode identity wins with preserved alternative and review")
func conflictingBarcodeIdentityRequiresReview() throws {
  let front = CardFieldResult(
    fullName: field("Alex Kim", confidence: 0.98, source: "front:name")
  )
  let back = try VCardParser().parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Jordan Lee\nEMAIL:jordan.lee@example.org\nEND:VCARD"
  )

  let result = CardScanSession().merge(front: front, back: back).merged

  #expect(result.fullName?.normalizedValue == "Jordan Lee")
  #expect(result.fullName?.alternativeCandidates.map(\.normalizedValue) == ["Alex Kim"])
  #expect(result.warnings.contains(.identityConflict))
  #expect(result.warnings.contains(.reviewRecommended))
}

@Test("Front-back merge is deterministic for reordered array values")
func frontBackMergeIsOrderIndependent() {
  let a = field("a@example.com", confidence: 0.9, source: "front:a")
  let b = field("b@example.com", confidence: 0.9, source: "front:b")
  let backA = field("A@example.com", confidence: 0.995, source: "barcode:a")
  let session = CardScanSession()

  let first = session.merge(
    front: CardFieldResult(emailAddresses: [a, b]),
    back: CardFieldResult(emailAddresses: [backA])
  ).merged
  let second = session.merge(
    front: CardFieldResult(emailAddresses: [b, a]),
    back: CardFieldResult(emailAddresses: [backA])
  ).merged

  #expect(first == second)
  #expect(first.emailAddresses.map(\.normalizedValue) == ["A@example.com", "b@example.com"])
}

private func field(
  _ value: String,
  confidence: Double,
  source: String
) -> ClassifiedValue {
  ClassifiedValue(
    normalizedValue: value,
    originalValue: value,
    confidence: confidence,
    evidence: [.syntaxMatch],
    sourceTokenIdentifiers: [source]
  )
}
