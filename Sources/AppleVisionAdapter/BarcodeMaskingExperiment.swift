import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(Vision)
  import CoreGraphics
  import Vision

  /// Chooses how QR/barcode regions are mapped before OCR tokens are classified.
  public enum AppleVisionBarcodeMaskingStrategy: String, Codable, Equatable, Sendable {
    /// Detect barcode regions again on the exact rectified recognition image.
    case rectifiedRedetection

    /// Experimental source-observation homography mapping. Invalid mappings fall back to
    /// `rectifiedRedetection` for safety.
    case projectiveSourceObservation
  }

  struct BarcodeMaskQuadrilateral: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint

    init(_ observation: VNBarcodeObservation) {
      self.init(
        topLeft: observation.topLeft,
        topRight: observation.topRight,
        bottomLeft: observation.bottomLeft,
        bottomRight: observation.bottomRight
      )
    }

    init(
      topLeft: CGPoint,
      topRight: CGPoint,
      bottomLeft: CGPoint,
      bottomRight: CGPoint
    ) {
      self.topLeft = topLeft
      self.topRight = topRight
      self.bottomLeft = bottomLeft
      self.bottomRight = bottomRight
    }

    var pointsInVisionOrder: [CGPoint] {
      [topLeft, topRight, bottomRight, bottomLeft]
    }

    var isFinite: Bool {
      pointsInVisionOrder.allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }

    var area: Double {
      guard isFinite else { return 0 }
      let points = pointsInVisionOrder
      var twiceArea = 0.0
      for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        twiceArea += Double(current.x * next.y - next.x * current.y)
      }
      return abs(twiceArea) / 2
    }
  }

  /// Maps source Vision barcode quadrilaterals into the normalized image produced by
  /// `CIPerspectiveCorrection`. This is deliberately pure so its safety gates can be tested
  /// without invoking Vision.
  enum ProjectiveBarcodeMaskMapper {
    static func regions(
      barcodes: [BarcodeMaskQuadrilateral],
      card: BarcodeMaskQuadrilateral
    ) -> [NormalizedBoundingBox]? {
      guard !barcodes.isEmpty, let homography = Homography(source: card) else { return nil }

      var regions: [NormalizedBoundingBox] = []
      for barcode in barcodes {
        guard let mapped = homography.map(barcode), let box = normalizedBox(mapped) else {
          return nil
        }
        regions.append(box)
      }
      return regions
    }

    private static func normalizedBox(_ points: [CGPoint]) -> NormalizedBoundingBox? {
      guard points.count == 4, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
        return nil
      }
      let minimumX = points.map(\.x).min() ?? 0
      let maximumX = points.map(\.x).max() ?? 0
      let minimumY = points.map(\.y).min() ?? 0
      let maximumY = points.map(\.y).max() ?? 0
      guard
        minimumX >= -0.05,
        minimumY >= -0.05,
        maximumX <= 1.05,
        maximumY <= 1.05,
        maximumX - minimumX > 0.000_001,
        maximumY - minimumY > 0.000_001
      else { return nil }

      let clampedMinX = min(max(minimumX, 0), 1)
      let clampedMaxX = min(max(maximumX, 0), 1)
      let clampedMinY = min(max(minimumY, 0), 1)
      let clampedMaxY = min(max(maximumY, 0), 1)
      guard clampedMaxX > clampedMinX, clampedMaxY > clampedMinY else { return nil }
      return NormalizedBoundingBox(
        x: Double(clampedMinX),
        y: Double(clampedMinY),
        width: Double(clampedMaxX - clampedMinX),
        height: Double(clampedMaxY - clampedMinY)
      )
    }
  }

  private struct Homography: Sendable {
    private let coefficients: [Double]

    init?(source card: BarcodeMaskQuadrilateral) {
      guard card.isFinite, card.area > 0.000_001 else { return nil }
      let sourcePoints = [card.topLeft, card.topRight, card.bottomRight, card.bottomLeft]
      let targetPoints = [
        CGPoint(x: 0, y: 1),
        CGPoint(x: 1, y: 1),
        CGPoint(x: 1, y: 0),
        CGPoint(x: 0, y: 0),
      ]
      var matrix: [[Double]] = []
      for (source, target) in zip(sourcePoints, targetPoints) {
        let x = Double(source.x)
        let y = Double(source.y)
        let u = Double(target.x)
        let v = Double(target.y)
        matrix.append([x, y, 1, 0, 0, 0, -u * x, -u * y, u])
        matrix.append([0, 0, 0, x, y, 1, -v * x, -v * y, v])
      }
      guard let solved = Self.solve(matrix) else { return nil }
      coefficients = solved
    }

    func map(_ barcode: BarcodeMaskQuadrilateral) -> [CGPoint]? {
      guard barcode.isFinite, barcode.area > 0.000_001 else { return nil }
      var mapped: [CGPoint] = []
      for point in barcode.pointsInVisionOrder {
        let x = Double(point.x)
        let y = Double(point.y)
        let denominator = coefficients[6] * x + coefficients[7] * y + 1
        guard denominator.isFinite, abs(denominator) > 0.000_000_001 else { return nil }
        let u = (coefficients[0] * x + coefficients[1] * y + coefficients[2]) / denominator
        let v = (coefficients[3] * x + coefficients[4] * y + coefficients[5]) / denominator
        guard u.isFinite, v.isFinite else { return nil }
        mapped.append(CGPoint(x: u, y: v))
      }
      return mapped
    }

    private static func solve(_ augmented: [[Double]]) -> [Double]? {
      guard augmented.count == 8, augmented.allSatisfy({ $0.count == 9 }) else { return nil }
      var matrix = augmented
      for column in 0..<8 {
        guard
          let pivot = (column..<8).max(by: { abs(matrix[$0][column]) < abs(matrix[$1][column]) }),
          abs(matrix[pivot][column]) > 0.000_000_000_1
        else { return nil }
        if pivot != column { matrix.swapAt(pivot, column) }

        let divisor = matrix[column][column]
        for index in column..<9 { matrix[column][index] /= divisor }
        for row in 0..<8 where row != column {
          let factor = matrix[row][column]
          guard factor.isFinite else { return nil }
          if abs(factor) <= 0.000_000_000_1 { continue }
          for index in column..<9 {
            matrix[row][index] -= factor * matrix[column][index]
          }
        }
      }
      let result = matrix.map { $0[8] }
      guard result.allSatisfy(\.isFinite) else { return nil }
      return result
    }
  }
#endif
