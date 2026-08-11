import Foundation

public enum CorrectionKind: String, Codable, Sendable {
  case emailDomainOrganization
  case organizationAlias
  case preferredNameOrdering
  case customJobTitle
  case phoneLabelInterpretation
  case reclassifyPattern
}

/// A minimal reusable correction. Hosts should avoid storing complete contact records.
public struct PersonalCorrection: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var kind: CorrectionKind
  public var match: String
  public var replacement: String?
  public var targetField: CardField?
  public var phoneKind: PhoneKind?

  public init(
    id: String,
    kind: CorrectionKind,
    match: String,
    replacement: String? = nil,
    targetField: CardField? = nil,
    phoneKind: PhoneKind? = nil
  ) {
    self.id = id
    self.kind = kind
    self.match = match
    self.replacement = replacement
    self.targetField = targetField
    self.phoneKind = phoneKind
  }
}

public protocol CorrectionStore: Sendable {
  func loadCorrections() throws -> [PersonalCorrection]
}

public struct EmptyCorrectionStore: CorrectionStore {
  public init() {}
  public func loadCorrections() -> [PersonalCorrection] { [] }
}

public final class InMemoryCorrectionStore: CorrectionStore, @unchecked Sendable {
  private let lock = NSLock()
  private var corrections: [PersonalCorrection]

  public init(corrections: [PersonalCorrection] = []) {
    self.corrections = corrections
  }

  public func loadCorrections() -> [PersonalCorrection] {
    lock.withLock { corrections }
  }

  public func replace(with corrections: [PersonalCorrection]) {
    lock.withLock { self.corrections = corrections }
  }
}

/// Optional local JSON storage. It performs no logging, telemetry, or network access.
public struct LocalJSONCorrectionStore: CorrectionStore {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func loadCorrections() throws -> [PersonalCorrection] {
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([PersonalCorrection].self, from: data)
  }
}
