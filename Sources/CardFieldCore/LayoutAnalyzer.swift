import Foundation

/// One visual row of OCR tokens grouped by vertical overlap.
public struct LayoutRow: Equatable, Sendable {
  /// Tokens ordered left-to-right within the row.
  public var tokens: [OCRToken]
  /// The union box covering every token in the row.
  public var boundingBox: NormalizedBoundingBox
}

/// Deterministic, geometry-only grouping of OCR tokens into visual rows and columns.
///
/// The analyzer never mutates token text or identifiers. Hosts can use it to reason
/// about multi-column card layouts where a single reading-order pass interleaves
/// left and right columns. All outputs follow the package determinism contract:
/// the same input always produces the same grouping without locale-global state.
public enum LayoutAnalyzer {
  /// Groups `tokens` into rows whose boxes overlap vertically by more than half of
  /// the shorter box height. Rows are ordered top-to-bottom, tokens left-to-right.
  public static func rows(in tokens: [OCRToken]) -> [LayoutRow] {
    var groups: [[OCRToken]] = []
    for token in tokens.sorted(by: readingOrder) {
      if let index = groups.lastIndex(where: { group in
        group.contains { shareRow($0.boundingBox, token.boundingBox) }
      }) {
        groups[index].append(token)
      } else {
        groups.append([token])
      }
    }

    return
      groups
      .map { group in
        group.sorted {
          if $0.boundingBox.x != $1.boundingBox.x { return $0.boundingBox.x < $1.boundingBox.x }
          return $0.id < $1.id
        }
      }
      .sorted {
        let firstBox = unionBox($0.map(\.boundingBox))
        let secondBox = unionBox($1.map(\.boundingBox))
        let firstTop = firstBox.y + firstBox.height
        let secondTop = secondBox.y + secondBox.height
        if abs(firstTop - secondTop) > 0.000_001 { return firstTop > secondTop }
        if firstBox.x != secondBox.x { return firstBox.x < secondBox.x }
        return ($0.first?.id ?? "") < ($1.first?.id ?? "")
      }
      .map { LayoutRow(tokens: $0, boundingBox: unionBox($0.map(\.boundingBox))) }
  }

  /// Splits one row into column runs separated by horizontal gaps of at least
  /// `minimumGap` of the card width.
  public static func columns(in row: LayoutRow, minimumGap: Double = 0.08) -> [[OCRToken]] {
    let ordered = row.tokens.sorted {
      if $0.boundingBox.x != $1.boundingBox.x { return $0.boundingBox.x < $1.boundingBox.x }
      return $0.id < $1.id
    }
    var runs: [[OCRToken]] = []
    for token in ordered {
      if let previous = runs.last?.last,
        token.boundingBox.x - (previous.boundingBox.x + previous.boundingBox.width)
          >= minimumGap
      {
        runs.append([token])
      } else if runs.last != nil {
        runs[runs.count - 1].append(token)
      } else {
        runs = [[token]]
      }
    }
    return runs
  }

  /// True when two boxes overlap vertically by more than half of the shorter height.
  static func shareRow(_ lhs: NormalizedBoundingBox, _ rhs: NormalizedBoundingBox) -> Bool {
    let overlapTop = min(lhs.y + lhs.height, rhs.y + rhs.height)
    let overlapBottom = max(lhs.y, rhs.y)
    let overlapHeight = overlapTop - overlapBottom
    guard overlapHeight > 0 else { return false }
    let shortestHeight = min(lhs.height, rhs.height)
    guard shortestHeight > 0 else { return false }
    return overlapHeight / shortestHeight > 0.5
  }

  static func readingOrder(_ lhs: OCRToken, _ rhs: OCRToken) -> Bool {
    if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.000_001 {
      return lhs.boundingBox.midY > rhs.boundingBox.midY
    }
    if lhs.boundingBox.x != rhs.boundingBox.x { return lhs.boundingBox.x < rhs.boundingBox.x }
    return lhs.id < rhs.id
  }

  private static func unionBox(_ boxes: [NormalizedBoundingBox]) -> NormalizedBoundingBox {
    guard let first = boxes.first else {
      return NormalizedBoundingBox(x: 0, y: 0, width: 0, height: 0)
    }
    let minX = boxes.map(\.x).min() ?? first.x
    let minY = boxes.map(\.y).min() ?? first.y
    let maxX = boxes.map { $0.x + $0.width }.max() ?? (first.x + first.width)
    let maxY = boxes.map { $0.y + $0.height }.max() ?? (first.y + first.height)
    return NormalizedBoundingBox(
      x: minX,
      y: minY,
      width: max(maxX - minX, 0),
      height: max(maxY - minY, 0)
    )
  }
}
