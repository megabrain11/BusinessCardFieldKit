import Foundation

/// A unit-square rectangle with an origin at the bottom-left of the upright card front.
public struct NormalizedBoundingBox: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var area: Double { width * height }
  public var midY: Double { y + height / 2 }

  public var isValid: Bool {
    x >= 0 && y >= 0 && width >= 0 && height >= 0 && x + width <= 1.000_001
      && y + height <= 1.000_001
  }
}

/// One OCR observation from the front of a card. The core never accepts card images.
public struct OCRToken: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var text: String
  public var boundingBox: NormalizedBoundingBox
  public var confidence: Double
  public var language: String?

  public init(
    id: String = "",
    text: String,
    boundingBox: NormalizedBoundingBox,
    confidence: Double,
    language: String? = nil
  ) {
    self.id = id
    self.text = text
    self.boundingBox = boundingBox
    self.confidence = confidence
    self.language = language
  }
}

public enum CardField: String, Codable, CaseIterable, Sendable {
  case fullName
  case alternateNames
  case preferredName
  case jobTitle
  case department
  case organization
  case emailAddresses
  case mobilePhoneNumbers
  case workPhoneNumbers
  case faxNumbers
  case websites
  case professionalProfileURLs
  case socialHandles
  case addresses
}

public enum Evidence: String, Codable, CaseIterable, Sendable {
  case syntaxMatch
  case nearJobTitle
  case matchesEmailLocalPart
  case emailDomainHint
  case precededByMobileLabel
  case precededByWorkLabel
  case precededByFaxLabel
  case organizationSuffix
  case organizationVocabulary
  case titleVocabulary
  case departmentVocabulary
  case addressVocabulary
  case layoutProminence
  case multilingualVariant
  case profileHost
  case socialPrefix
  case localeRulePack
  case industryRulePack
  case userCorrection
}

public struct AlternativeCandidate: Codable, Equatable, Sendable {
  public var normalizedValue: String
  public var originalValue: String
  public var confidence: Double
  public var evidence: [Evidence]
  public var sourceTokenIdentifiers: [String]

  public init(
    normalizedValue: String,
    originalValue: String,
    confidence: Double,
    evidence: [Evidence],
    sourceTokenIdentifiers: [String]
  ) {
    self.normalizedValue = normalizedValue
    self.originalValue = originalValue
    self.confidence = confidence
    self.evidence = evidence
    self.sourceTokenIdentifiers = sourceTokenIdentifiers
  }
}

public struct ClassifiedValue: Codable, Equatable, Sendable {
  public var normalizedValue: String
  public var originalValue: String
  public var confidence: Double
  public var evidence: [Evidence]
  public var alternativeCandidates: [AlternativeCandidate]
  public var sourceTokenIdentifiers: [String]

  public init(
    normalizedValue: String,
    originalValue: String,
    confidence: Double,
    evidence: [Evidence],
    alternativeCandidates: [AlternativeCandidate] = [],
    sourceTokenIdentifiers: [String]
  ) {
    self.normalizedValue = normalizedValue
    self.originalValue = originalValue
    self.confidence = min(max(confidence, 0), 1)
    self.evidence = Array(Set(evidence)).sorted { $0.rawValue < $1.rawValue }
    self.alternativeCandidates = alternativeCandidates
    self.sourceTokenIdentifiers = sourceTokenIdentifiers
  }
}

public enum CardFieldWarning: String, Codable, Equatable, Sendable {
  case noVisiblePersonName
  case ambiguousPersonName
  case ambiguousPhoneNumber
  case lowConfidenceFields
  case invalidBoundingBox
  case emptyInput
}

public struct CardFieldResult: Codable, Equatable, Sendable {
  public var contractVersion: String
  public var ruleVersions: [String]
  public var fullName: ClassifiedValue?
  public var alternateNames: [ClassifiedValue]
  public var preferredName: ClassifiedValue?
  public var jobTitle: ClassifiedValue?
  public var department: ClassifiedValue?
  public var organization: ClassifiedValue?
  public var emailAddresses: [ClassifiedValue]
  public var mobilePhoneNumbers: [ClassifiedValue]
  public var workPhoneNumbers: [ClassifiedValue]
  public var faxNumbers: [ClassifiedValue]
  public var websites: [ClassifiedValue]
  public var professionalProfileURLs: [ClassifiedValue]
  public var socialHandles: [ClassifiedValue]
  public var addresses: [ClassifiedValue]
  public var unclassifiedLines: [OCRToken]
  public var warnings: [CardFieldWarning]
  public var overallConfidence: Double

  public init(
    contractVersion: String = "1.0",
    ruleVersions: [String] = [],
    fullName: ClassifiedValue? = nil,
    alternateNames: [ClassifiedValue] = [],
    preferredName: ClassifiedValue? = nil,
    jobTitle: ClassifiedValue? = nil,
    department: ClassifiedValue? = nil,
    organization: ClassifiedValue? = nil,
    emailAddresses: [ClassifiedValue] = [],
    mobilePhoneNumbers: [ClassifiedValue] = [],
    workPhoneNumbers: [ClassifiedValue] = [],
    faxNumbers: [ClassifiedValue] = [],
    websites: [ClassifiedValue] = [],
    professionalProfileURLs: [ClassifiedValue] = [],
    socialHandles: [ClassifiedValue] = [],
    addresses: [ClassifiedValue] = [],
    unclassifiedLines: [OCRToken] = [],
    warnings: [CardFieldWarning] = [],
    overallConfidence: Double = 0
  ) {
    self.contractVersion = contractVersion
    self.ruleVersions = ruleVersions
    self.fullName = fullName
    self.alternateNames = alternateNames
    self.preferredName = preferredName
    self.jobTitle = jobTitle
    self.department = department
    self.organization = organization
    self.emailAddresses = emailAddresses
    self.mobilePhoneNumbers = mobilePhoneNumbers
    self.workPhoneNumbers = workPhoneNumbers
    self.faxNumbers = faxNumbers
    self.websites = websites
    self.professionalProfileURLs = professionalProfileURLs
    self.socialHandles = socialHandles
    self.addresses = addresses
    self.unclassifiedLines = unclassifiedLines
    self.warnings = warnings
    self.overallConfidence = min(max(overallConfidence, 0), 1)
  }

  public func values(for field: CardField) -> [ClassifiedValue] {
    switch field {
    case .fullName: fullName.map { [$0] } ?? []
    case .alternateNames: alternateNames
    case .preferredName: preferredName.map { [$0] } ?? []
    case .jobTitle: jobTitle.map { [$0] } ?? []
    case .department: department.map { [$0] } ?? []
    case .organization: organization.map { [$0] } ?? []
    case .emailAddresses: emailAddresses
    case .mobilePhoneNumbers: mobilePhoneNumbers
    case .workPhoneNumbers: workPhoneNumbers
    case .faxNumbers: faxNumbers
    case .websites: websites
    case .professionalProfileURLs: professionalProfileURLs
    case .socialHandles: socialHandles
    case .addresses: addresses
    }
  }
}
