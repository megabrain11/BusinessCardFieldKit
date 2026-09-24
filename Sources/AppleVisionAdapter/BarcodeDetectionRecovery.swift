import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(Vision)
  import CoreGraphics
  import CoreImage

  /// Default-off preprocessing used for one bounded barcode retry after an empty source result.
  public struct AppleVisionBarcodeDetectionRecoveryOptions: Equatable, Sendable {
    public var isEnabled: Bool
    public var minimumLongEdge: Int
    public var maximumLongEdge: Int
    public var contrastAdjustment: Double
    public var sharpeningIntensity: Double
    public var usesOtsuBinarization: Bool

    public init(
      isEnabled: Bool = false,
      minimumLongEdge: Int = 3_200,
      maximumLongEdge: Int = 4_096,
      contrastAdjustment: Double = 0.6,
      sharpeningIntensity: Double = 0.9,
      usesOtsuBinarization: Bool = true
    ) {
      self.isEnabled = isEnabled
      self.minimumLongEdge = min(max(minimumLongEdge, 0), 8_192)
      self.maximumLongEdge = min(
        max(maximumLongEdge, max(self.minimumLongEdge, 1_024)),
        8_192
      )
      self.contrastAdjustment = min(max(contrastAdjustment, 0), 1)
      self.sharpeningIntensity = min(max(sharpeningIntensity, 0), 2)
      self.usesOtsuBinarization = usesOtsuBinarization
    }
  }

  enum BarcodeDetectionRecoveryPreprocessor {
    static func preprocess(
      _ image: CGImage,
      options: AppleVisionBarcodeDetectionRecoveryOptions
    ) -> CGImage? {
      guard options.isEnabled else { return nil }
      var working = CIImage(cgImage: image)
      let longEdge = max(working.extent.width, working.extent.height)
      if longEdge > 0, longEdge < CGFloat(options.minimumLongEdge) {
        let target = min(CGFloat(options.minimumLongEdge), CGFloat(options.maximumLongEdge))
        let scale = target / longEdge
        working = working.transformed(
          by: CGAffineTransform(scaleX: scale, y: scale),
          highQualityDownsample: true
        )
      }

      if let controls = CIFilter(name: "CIColorControls") {
        controls.setValue(working, forKey: kCIInputImageKey)
        controls.setValue(0, forKey: kCIInputSaturationKey)
        controls.setValue(1 + options.contrastAdjustment, forKey: kCIInputContrastKey)
        if let output = controls.outputImage { working = output }
      }
      if options.sharpeningIntensity > 0,
        let sharpen = CIFilter(name: "CISharpenLuminance")
      {
        sharpen.setValue(working, forKey: kCIInputImageKey)
        sharpen.setValue(options.sharpeningIntensity, forKey: kCIInputSharpnessKey)
        if let output = sharpen.outputImage { working = output }
      }
      if options.usesOtsuBinarization,
        let threshold = CIFilter(name: "CIColorThresholdOtsu")
      {
        threshold.setValue(working, forKey: kCIInputImageKey)
        if let output = threshold.outputImage { working = output }
      }
      return ImagePreprocessor.sharedContext.createCGImage(
        working,
        from: working.extent.integral
      )
    }
  }
#endif
