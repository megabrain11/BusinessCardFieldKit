import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  import CoreGraphics
  import CoreImage
  import Vision

  /// Configuration for the local image-enhancement pass applied before text recognition.
  ///
  /// Small card crops and glossy photos frequently produce text below reliable
  /// recognition height. The pipeline upscales small images, removes color noise,
  /// raises contrast, and sharpens strokes with Core Image filters.
  public struct AppleVisionPreprocessingConfiguration: Equatable, Sendable {
    /// Whether preprocessing runs at all. Disabling keeps legacy single-pass behavior.
    public var isEnabled: Bool

    /// Minimum long-edge pixel size targeted by upscaling, clamped to `0...8192`.
    /// `0` disables upscaling.
    public var minimumLongEdge: Int

    /// Hard ceiling for any produced long edge, clamped to be at least
    /// `minimumLongEdge` and `1024`.
    public var maximumLongEdge: Int

    /// Whether color information is discarded before recognition.
    public var convertsToGrayscale: Bool

    /// Contrast adjustment supplied to Core Image color controls, clamped to `-1...1`.
    public var contrastAdjustment: Double

    /// Unsharp-mask intensity applied after scaling, clamped to `0...2`. `0` disables it.
    public var sharpeningIntensity: Double

    public init(
      isEnabled: Bool = true,
      minimumLongEdge: Int = 1_600,
      maximumLongEdge: Int = 4_096,
      convertsToGrayscale: Bool = true,
      contrastAdjustment: Double = 0.08,
      sharpeningIntensity: Double = 0.5
    ) {
      self.isEnabled = isEnabled
      self.minimumLongEdge = min(max(minimumLongEdge, 0), 8_192)
      let cappedMaximum = max(maximumLongEdge, max(self.minimumLongEdge, 1_024))
      self.maximumLongEdge = min(cappedMaximum, 8_192)
      self.convertsToGrayscale = convertsToGrayscale
      self.contrastAdjustment = min(max(contrastAdjustment, -1), 1)
      self.sharpeningIntensity = min(max(sharpeningIntensity, 0), 2)
    }
  }

  /// Applies deterministic local Core Image enhancement before recognition.
  ///
  /// The shared `CIContext` is process-wide because Apple documents `CIContext`
  /// as thread-safe; recreating it per scan dominates latency on large batches.
  enum ImagePreprocessor {
    nonisolated(unsafe) static let sharedContext = CIContext()

    static func preprocess(
      _ image: CGImage,
      configuration: AppleVisionPreprocessingConfiguration
    ) -> CGImage {
      guard configuration.isEnabled else { return image }
      var working = CIImage(cgImage: image)

      if let scaled = upscaled(working, configuration: configuration) {
        working = scaled
      }

      if configuration.convertsToGrayscale || configuration.contrastAdjustment != 0,
        let controls = CIFilter(name: "CIColorControls")
      {
        controls.setValue(working, forKey: kCIInputImageKey)
        if configuration.convertsToGrayscale {
          controls.setValue(0.0, forKey: kCIInputSaturationKey)
        }
        controls.setValue(1.0 + configuration.contrastAdjustment, forKey: kCIInputContrastKey)
        if let output = controls.outputImage {
          working = output
        }
      }

      if configuration.sharpeningIntensity > 0,
        let unsharp = CIFilter(name: "CIUnsharpMask")
      {
        unsharp.setValue(working, forKey: kCIInputImageKey)
        unsharp.setValue(configuration.sharpeningIntensity, forKey: "inputIntensity")
        unsharp.setValue(
          2.0 * scaleRatio(for: working.extent.size, configuration: configuration),
          forKey: "inputRadius")
        if let output = unsharp.outputImage {
          working = output.cropped(to: working.extent)
        }
      }

      let extent = working.extent.integral
      guard extent.width.isFinite, extent.height.isFinite, extent.width >= 1, extent.height >= 1
      else { return image }
      return sharedContext.createCGImage(working, from: extent) ?? image
    }

    static func upscale(_ image: CGImage, targetLongEdge: Int) -> CGImage? {
      guard targetLongEdge > 0 else { return nil }
      let longEdge = max(image.width, image.height)
      guard longEdge > 0, longEdge < targetLongEdge else { return nil }
      let ratio = CGFloat(targetLongEdge) / CGFloat(longEdge)
      guard ratio.isFinite, ratio > 1 else { return nil }
      return rendered(
        CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
      )
    }

    private static func upscaled(
      _ image: CIImage,
      configuration: AppleVisionPreprocessingConfiguration
    ) -> CIImage? {
      guard configuration.minimumLongEdge > 0 else { return nil }
      let extent = image.extent
      let longEdge = max(extent.width, extent.height)
      guard longEdge.isFinite, longEdge > 0, longEdge < CGFloat(configuration.minimumLongEdge)
      else { return nil }

      var ratio = CGFloat(configuration.minimumLongEdge) / longEdge
      let maximumEdge = CGFloat(configuration.maximumLongEdge)
      if longEdge * ratio > maximumEdge {
        ratio = maximumEdge / longEdge
      }
      guard ratio.isFinite, ratio > 1 else { return nil }
      return image.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
    }

    private static func scaleRatio(
      for size: CGSize,
      configuration: AppleVisionPreprocessingConfiguration
    ) -> CGFloat {
      guard configuration.minimumLongEdge > 0 else { return 1 }
      let longEdge = max(size.width, size.height)
      guard longEdge.isFinite, longEdge > 0 else { return 1 }
      let ratio = longEdge / CGFloat(configuration.minimumLongEdge)
      return min(max(ratio, 1), 3)
    }

    private static func rendered(_ image: CIImage) -> CGImage? {
      let extent = image.extent.integral
      guard extent.width.isFinite, extent.height.isFinite, extent.width >= 1, extent.height >= 1
      else { return nil }
      return sharedContext.createCGImage(image, from: extent)
    }
  }
#endif
