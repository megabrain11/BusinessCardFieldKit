# OCR Adapter Guide

The provider-conversion boundary emits `OCRToken` values. A full scanner may orchestrate local recognition and classification, but provider types and image handling must remain outside `CardFieldCore`.

For each visible front-side observation provide:

- Stable identifier, or leave it empty for deterministic positional assignment
- Original OCR text
- Bottom-left normalized bounding box
- Confidence from `0` to `1`
- Optional BCP 47 language tag

## Apple Vision

For an end-to-end local scan, create `AppleVisionScanner` and call either:

```swift
let encodedScan = try scanner.scan(imageData: frontImageData)
let decodedScan = try scanner.scan(cgImage: frontCGImage, orientation: .right)
```

`scan(imageData:orientation:)` validates the encoded image and reads EXIF orientation when the argument is `nil`. Foreground-card isolation is enabled by default: the scanner asks `VNDetectRectanglesRequest` for a bounded set of plausible business-card quadrilaterals, ranks them by aspect ratio, area, centrality, and confidence, perspective-corrects the strongest candidates locally, and uses contact-text cohesion to select one candidate. Email, phone, website, title, and address signals help a complete foreground card outrank a partial background card. It then converts the selected card's recognized lines to `OCRToken` and calls the injected `CardFieldClassifier`.

The detector is intentionally bounded and conservative. `maximumObservations` limits Vision results, `maximumTextRecognitionCandidates` limits the more expensive OCR passes, and `minimumTextEvidenceScore` prevents an arbitrary text-bearing rectangle from being accepted without enough contact-card evidence. Configure or disable the behavior through `AppleVisionCardRegionConfiguration`:

```swift
let configuration = AppleVisionScanConfiguration(
  recognitionLanguages: ["ko-KR", "en-US"],
  cardRegion: AppleVisionCardRegionConfiguration(
    mode: .automatic,
    maximumObservations: 8,
    maximumTextRecognitionCandidates: 4
  )
)
let scanner = AppleVisionScanner(configuration: configuration)
```

If no plausible text-bearing card can be corrected, the scanner safely falls back to OCR over the full source image. Set `mode: .disabled` when the host has already cropped and perspective-corrected a single card. `AppleVisionScanResult.cardRegionSelection` reports `.isolated` with its normalized upright source bounding box and selection score, `.fullImageFallback`, or `.disabled`. Token bounding boxes are relative to the selected, corrected card when isolation succeeds and relative to the full upright image otherwise.

The returned `AppleVisionScanResult` contains `tokens`, structured `fields`, and this region-selection metadata.

Use `AppleVisionScanConfiguration` to select accurate or fast recognition, provide ordered BCP 47 language hints, enable automatic language detection and correction, set a minimum relative text height, or attach a host-provided language tag to emitted tokens. Vision does not expose a detected language for each recognized candidate, so `tokenLanguage` is only an explicit host hint.

The scanner is synchronous and should run away from latency-sensitive UI work. It performs no capture, persistence, logging, or networking, and it retains no image after the call. It reports invalid encoded data, no recognized text, Vision failures, and classifier failures as `AppleVisionScanError` values.

If the host already performed the Vision request, use `AppleVisionAdapter.tokens(from:language:)` and call `CardFieldClassifier` directly. Apple Vision already uses normalized bottom-left coordinates.

## Google ML Kit

Divide pixel coordinates by the upright image width and height. Convert ML Kit's top-left `top` coordinate to `y = 1 - top / imageHeight - height / imageHeight`. Keep image rotation correction in the adapter.

## Tesseract

Convert the selected page or image bounding boxes to the same unit square. Tesseract confidence scales vary by API; clamp or calibrate them to `0...1` and document the mapping.

## Web or cloud OCR

Map the provider response locally when possible. If OCR itself requires upload, the host—not this package—must provide consent, retention, access, deletion, and processor disclosures. Never imply that a cloud OCR adapter is local.

Adapters must analyze only the card front. Back-image behavior and the decision to retain or discard source images belong to the host application.
