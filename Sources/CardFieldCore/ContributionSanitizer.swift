import Foundation

public struct SanitizedContributionToken: Codable, Equatable, Sendable {
  public var placeholder: String
  public var boundingBox: NormalizedBoundingBox
  public var confidenceBucket: String
  public var language: String?

  public init(
    placeholder: String,
    boundingBox: NormalizedBoundingBox,
    confidenceBucket: String,
    language: String?
  ) {
    self.placeholder = placeholder
    self.boundingBox = boundingBox
    self.confidenceBucket = confidenceBucket
    self.language = language
  }
}

public struct SanitizedCorrectionSummary: Codable, Equatable, Sendable {
  public var kind: CorrectionKind
  public var targetField: CardField?

  public init(kind: CorrectionKind, targetField: CardField?) {
    self.kind = kind
    self.targetField = targetField
  }
}

/// A local, reviewable draft. Sharing is deliberately outside this library.
public struct ContributionDraft: Codable, Equatable, Sendable {
  public var schemaVersion: String
  public var tokens: [SanitizedContributionToken]
  public var corrections: [SanitizedCorrectionSummary]
  public var warnings: [String]

  public init(
    schemaVersion: String = "1.0",
    tokens: [SanitizedContributionToken],
    corrections: [SanitizedCorrectionSummary],
    warnings: [String]
  ) {
    self.schemaVersion = schemaVersion
    self.tokens = tokens
    self.corrections = corrections
    self.warnings = warnings
  }
}

public enum ContributionSanitizer {
  public static func makeDraft(
    observations: [OCRToken],
    result: CardFieldResult,
    corrections: [PersonalCorrection] = []
  ) -> ContributionDraft {
    let fieldByToken = placeholderMap(result: result)
    let tokens = OCRNormalizer.normalize(observations).map { token in
      SanitizedContributionToken(
        placeholder: fieldByToken[token.id] ?? "<UNCLASSIFIED>",
        boundingBox: token.boundingBox,
        confidenceBucket: confidenceBucket(token.confidence),
        language: sanitizedLanguage(token.language)
      )
    }
    let summaries = corrections.map {
      SanitizedCorrectionSummary(kind: $0.kind, targetField: $0.targetField)
    }
    return ContributionDraft(
      tokens: tokens,
      corrections: summaries,
      warnings: [
        "Review this draft before sharing.",
        "Do not attach the original image, OCR text, or personal correction file.",
      ]
    )
  }

  private static func placeholderMap(result: CardFieldResult) -> [String: String] {
    let ordered: [(CardField, String)] = [
      (.fullName, "<PERSON_NAME>"), (.alternateNames, "<PERSON_NAME>"),
      (.preferredName, "<PERSON_NAME>"), (.jobTitle, "<JOB_TITLE>"),
      (.department, "<DEPARTMENT>"), (.organization, "<ORGANIZATION>"),
      (.mobilePhoneNumbers, "<MOBILE_PHONE>"), (.workPhoneNumbers, "<WORK_PHONE>"),
      (.faxNumbers, "<FAX>"), (.emailAddresses, "<EMAIL>"),
      (.professionalProfileURLs, "<PROFESSIONAL_PROFILE_URL>"),
      (.websites, "<WEBSITE>"), (.socialHandles, "<SOCIAL_HANDLE>"),
      (.addresses, "<ADDRESS>"),
    ]
    var map: [String: String] = [:]
    for (field, placeholder) in ordered {
      for value in result.values(for: field) {
        for identifier in value.sourceTokenIdentifiers where map[identifier] == nil {
          map[identifier] = placeholder
        }
      }
    }
    return map
  }

  private static func confidenceBucket(_ confidence: Double) -> String {
    if confidence >= 0.9 { return "high" }
    if confidence >= 0.7 { return "medium" }
    return "low"
  }

  private static func sanitizedLanguage(_ language: String?) -> String? {
    guard let language else { return nil }
    return String(language.prefix(16)).filter { $0.isLetter || $0 == "-" }
  }
}
