import Foundation

/// Configuration for the layout-aware classification path.
public struct ColumnAwareClassifierOptions: Equatable, Sendable {
  public enum Mode: String, Codable, Sendable {
    case disabled
    case enabled
  }

  public enum Strategy: String, Codable, Sendable {
    /// Legacy result plus conservative layout-recovered values.
    case conservative
    /// Legacy result plus layout-recovered values with wider geometric tolerance.
    case balanced
  }

  public var mode: Mode
  public var strategy: Strategy

  public init(mode: Mode = .disabled, strategy: Strategy = .conservative) {
    self.mode = mode
    self.strategy = strategy
  }
}

/// The regular classification result plus diagnostics from the optional
/// layout-aware pass. Diagnostics are returned per invocation so classifier
/// instances remain immutable and safe to share across tasks.
public struct ColumnAwareClassification: Equatable, Sendable {
  public var result: CardFieldResult
  public var diagnostics: ColumnAwareDiagnostics?

  public init(result: CardFieldResult, diagnostics: ColumnAwareDiagnostics?) {
    self.result = result
    self.diagnostics = diagnostics
  }
}

/// A label observation paired with its classified phone kind.
public struct ColumnAwarePhoneLabel: Equatable, Sendable {
  public var text: String
  public var kind: PhoneKind
  public var tokenIdentifier: String

  public init(text: String, kind: PhoneKind, tokenIdentifier: String) {
    self.text = text
    self.kind = kind
    self.tokenIdentifier = tokenIdentifier
  }
}

/// Deterministic diagnostics for one column-aware classification run.
public struct ColumnAwareDiagnostics: Codable, Equatable, Sendable {
  public var mode: String
  public var strategy: String
  public var layoutConfidence: Double
  public var rowCount: Int
  public var multiColumnRowCount: Int
  public var candidateCount: Int
  public var recoveredValueCount: Int
  public var conflictCount: Int
  public var usedFallback: Bool
  public var fallbackReason: String?

  public init(
    mode: String,
    strategy: String,
    layoutConfidence: Double = 0,
    rowCount: Int = 0,
    multiColumnRowCount: Int = 0,
    candidateCount: Int = 0,
    recoveredValueCount: Int = 0,
    conflictCount: Int = 0,
    usedFallback: Bool = false,
    fallbackReason: String? = nil
  ) {
    self.mode = mode
    self.strategy = strategy
    self.layoutConfidence = min(max(layoutConfidence, 0), 1)
    self.rowCount = rowCount
    self.multiColumnRowCount = multiColumnRowCount
    self.candidateCount = candidateCount
    self.recoveredValueCount = recoveredValueCount
    self.conflictCount = conflictCount
    self.usedFallback = usedFallback
    self.fallbackReason = fallbackReason
  }
}

/// A scored phone label-value pair produced from row and column geometry.
public struct LabelValueCandidate: Equatable, Sendable {
  public var labelToken: OCRToken
  public var valueToken: OCRToken
  public var score: Double
  public var relationship: Relationship

  public enum Relationship: String, Sendable {
    case sameRowAcrossColumns
    case sameRow
    case adjacentRow
    case nearbyRow
  }
}

/// Layout-aware scoring engine over `LayoutAnalyzer` clusters.
///
/// Version 1 deliberately links phone labels only. Email, URL, address, and
/// identity association remain on the legacy path until separate evidence and
/// regression coverage exist for those field families.
public enum ColumnAwareScoringEngine {
  /// Minimum estimated layout coherence required to apply layout-aware rules.
  public static let minimumLayoutConfidence = 0.55

  static func layoutConfidence(
    rows: [LayoutRow],
    tokens: [OCRToken],
    strategy: ColumnAwareClassifierOptions.Strategy
  ) -> Double {
    guard !rows.isEmpty else { return 0 }
    let meanConfidence = tokens.map(\.confidence).reduce(0, +) / Double(max(tokens.count, 1))
    let clustered = Set(rows.flatMap { $0.tokens.map(\.id) })
    let coverage = Double(clustered.count) / Double(max(tokens.count, 1))
    var alignmentPenalty = 0.0
    for row in rows where row.tokens.count > 1 {
      let midYs = row.tokens.map(\.boundingBox.midY)
      let spread = (midYs.max() ?? 0) - (midYs.min() ?? 0)
      let referenceHeight = row.tokens.map(\.boundingBox.height).max() ?? 0.03
      let limit =
        strategy == .balanced
        ? max(0.055, referenceHeight * 1.1)
        : max(0.04, referenceHeight * 0.8)
      if spread > limit {
        alignmentPenalty += min(0.2, spread - limit)
      }
    }
    return min(max(meanConfidence * 0.7 + coverage * 0.3 - alignmentPenalty, 0), 1)
  }

  /// Scores plausible phone label-value pairings across analyzed rows and columns.
  public static func candidates(
    for tokens: [OCRToken],
    labels: [ColumnAwarePhoneLabel],
    strategy: ColumnAwareClassifierOptions.Strategy = .conservative
  ) -> [LabelValueCandidate] {
    guard !labels.isEmpty else { return [] }
    let rows = LayoutAnalyzer.rows(in: tokens)
    let positions = layoutPositions(rows: rows, strategy: strategy)
    let phoneValues = tokens.filter { bareNumber(in: $0) != nil }
    let minimumScore = strategy == .balanced ? 0.42 : 0.52
    var candidates: [LabelValueCandidate] = []
    for label in labels {
      guard let labelToken = tokens.first(where: { $0.id == label.tokenIdentifier }) else {
        continue
      }
      for value in phoneValues where value.id != label.tokenIdentifier {
        guard
          let relationship = relationship(
            between: labelToken,
            and: value,
            positions: positions
          )
        else { continue }
        let score = candidateScore(
          label: labelToken,
          value: value,
          relationship: relationship
        )
        guard score >= minimumScore else { continue }
        candidates.append(
          LabelValueCandidate(
            labelToken: labelToken,
            valueToken: value,
            score: score,
            relationship: relationship
          )
        )
      }
    }
    return candidates.sorted {
      if $0.score != $1.score { return $0.score > $1.score }
      if $0.labelToken.id != $1.labelToken.id { return $0.labelToken.id < $1.labelToken.id }
      return $0.valueToken.id < $1.valueToken.id
    }
  }

  static func bareNumber(in token: OCRToken) -> Substring? {
    guard
      let range = token.text.range(
        of: #"(?:\+?\d[\d ()\-.]{5,}\d)"#,
        options: .regularExpression
      )
    else { return nil }
    let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let prefix = String(token.text[..<range.lowerBound]).trimmingCharacters(in: ignored)
    let suffix = String(token.text[range.upperBound...]).trimmingCharacters(in: ignored)
    guard prefix.isEmpty && suffix.isEmpty else { return nil }
    return token.text[range]
  }

  private struct LayoutPosition {
    var row: Int
    var column: Int
    var columnCount: Int
  }

  private static func layoutPositions(
    rows: [LayoutRow],
    strategy: ColumnAwareClassifierOptions.Strategy
  ) -> [String: LayoutPosition] {
    var positions: [String: LayoutPosition] = [:]
    let minimumGap = strategy == .balanced ? 0.06 : 0.08
    for (rowIndex, row) in rows.enumerated() {
      let columns = LayoutAnalyzer.columns(in: row, minimumGap: minimumGap)
      for (columnIndex, column) in columns.enumerated() {
        for token in column {
          positions[token.id] = LayoutPosition(
            row: rowIndex,
            column: columnIndex,
            columnCount: columns.count
          )
        }
      }
    }
    return positions
  }

  private static func relationship(
    between label: OCRToken,
    and value: OCRToken,
    positions: [String: LayoutPosition]
  ) -> LabelValueCandidate.Relationship? {
    guard label.boundingBox.isValid, value.boundingBox.isValid,
      let labelPosition = positions[label.id],
      let valuePosition = positions[value.id]
    else { return nil }

    let verticalDistance = abs(label.boundingBox.midY - value.boundingBox.midY)
    if labelPosition.row == valuePosition.row {
      if labelPosition.columnCount > 1, labelPosition.column != valuePosition.column {
        return .sameRowAcrossColumns
      }
      let horizontalGap = max(
        value.boundingBox.x - (label.boundingBox.x + label.boundingBox.width),
        label.boundingBox.x - (value.boundingBox.x + value.boundingBox.width),
        0
      )
      let rowTolerance = max(0.035, min(label.boundingBox.height, value.boundingBox.height))
      return verticalDistance <= rowTolerance && horizontalGap <= 0.20 ? .sameRow : nil
    }

    let rowDistance = abs(labelPosition.row - valuePosition.row)
    let labelCenterX = label.boundingBox.x + label.boundingBox.width / 2
    let valueCenterX = value.boundingBox.x + value.boundingBox.width / 2
    let centerAligned = abs(labelCenterX - valueCenterX) <= 0.14
    let leadingEdgesAligned = abs(label.boundingBox.x - value.boundingBox.x) <= 0.10
    guard centerAligned || leadingEdgesAligned else { return nil }
    if rowDistance == 1, verticalDistance <= 0.16 { return .adjacentRow }
    if rowDistance <= 2, verticalDistance <= 0.24 { return .nearbyRow }
    return nil
  }

  private static func candidateScore(
    label: OCRToken,
    value: OCRToken,
    relationship: LabelValueCandidate.Relationship
  ) -> Double {
    let horizontalGap = max(
      value.boundingBox.x - (label.boundingBox.x + label.boundingBox.width),
      label.boundingBox.x - (value.boundingBox.x + value.boundingBox.width),
      0
    )
    let verticalGap = max(
      label.boundingBox.y - (value.boundingBox.y + value.boundingBox.height),
      value.boundingBox.y - (label.boundingBox.y + label.boundingBox.height),
      0
    )
    var score = 0.0
    switch relationship {
    case .sameRowAcrossColumns:
      score = 0.52 + max(0, 0.12 - horizontalGap)
    case .sameRow:
      score = 0.42 + max(0, 0.10 - horizontalGap)
    case .adjacentRow:
      score = 0.34 + max(0, 0.08 - verticalGap)
    case .nearbyRow:
      score = 0.18 + max(0, 0.06 - verticalGap)
    }
    let labelCenterX = label.boundingBox.x + label.boundingBox.width / 2
    let valueCenterX = value.boundingBox.x + value.boundingBox.width / 2
    if abs(labelCenterX - valueCenterX) <= 0.18 {
      score += 0.06
    } else if label.boundingBox.x <= value.boundingBox.x {
      score += 0.04
    }
    score += value.confidence * 0.15
    return min(max(score, 0), 1)
  }
}
