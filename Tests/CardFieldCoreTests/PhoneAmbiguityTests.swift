import CardFieldCore
import Testing

@Test("An unlabeled phone remains unresolved instead of becoming a work phone")
func unlabeledPhoneRemainsUnresolved() throws {
  let observation = OCRToken(
    id: "unlabeled-phone",
    text: "+1 202 555 0188",
    boundingBox: .init(x: 0.1, y: 0.2, width: 0.4, height: 0.05),
    confidence: 0.97,
    language: "en"
  )

  let result = try CardFieldClassifier().classify([observation])

  #expect(result.mobilePhoneNumbers.isEmpty)
  #expect(result.workPhoneNumbers.isEmpty)
  #expect(result.faxNumbers.isEmpty)
  #expect(result.unclassifiedLines.map(\.id) == ["unlabeled-phone"])
  #expect(result.warnings.contains(.ambiguousPhoneNumber))
}

@Test("Phone labels are matched as complete labels instead of arbitrary suffixes")
func phoneLabelsUseBoundaries() throws {
  let observation = OCRToken(
    id: "room-number",
    text: "Room +1 202 555 0188",
    boundingBox: .init(x: 0.1, y: 0.2, width: 0.5, height: 0.05),
    confidence: 0.97,
    language: "en"
  )

  let result = try CardFieldClassifier().classify([observation])

  #expect(result.mobilePhoneNumbers.isEmpty)
  #expect(result.warnings.contains(.ambiguousPhoneNumber))
}
