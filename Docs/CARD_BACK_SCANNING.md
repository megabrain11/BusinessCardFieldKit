# Card-back scanning

`CardBackScanner` is an optional Apple-platform adapter for a separately captured card-back image. It runs local text recognition plus `VNDetectBarcodesRequest`, converts supported payloads into `CardFieldResult`, and retains neither the image nor decoded payload.

## Supported payloads

- vCard 3.0 and 4.0: `FN`, `N`, `ORG`, `TITLE`, `TEL`, `EMAIL`, `ADR`, and `URL`
- Explicit `http://` or `https://` URLs
- UTF-8 and EUC-KR input bytes in the provider-neutral `VCardParser`
- Folded vCard lines, escaped separators, and UTF-8/EUC-KR quoted-printable values

Unsupported barcode payloads produce content-free metadata only: symbology, payload kind, and normalized geometry. Raw barcode content is not part of the result contract.

## Usage

```swift
import AppleVisionAdapter
import CardFieldCore

let front = try AppleVisionScanner().scan(imageData: frontData)
let back = try CardBackScanner().scan(imageData: backData)
let combined = CardScanSession().merge(front: front.fields, back: back.fields)

if combined.merged.warnings.contains(.reviewRecommended) {
  // Present both sourced candidates to the user.
}
```

The host owns capture, side association, review, retention, and any eventual contact write. The package does not access the camera or Contacts framework.

## Merge behavior

- Values normalize to deterministic identity keys; phone numbers compare by digits.
- A value appearing on both sides is emitted once.
- Barcode-derived duplicates outrank OCR-derived duplicates because the payload is structured.
- A barcode phone subtype replaces a duplicate OCR subtype rather than emitting the same number twice.
- Conflicting singular values keep the barcode value, preserve the OCR value as an alternative candidate, and add `reviewRecommended`; name conflicts also add `identityConflict`.
- Array output, rule versions, evidence, and warnings are stably ordered.

These rules combine evidence from the two sides of one physical card. They do not resolve or merge separate people or contact records.

## Privacy boundary

Tests render only fictional QR data under `example.com`, `example.org`, and `555` numbers. Real card backs may be scanned transiently by a host, but their images, payloads, OCR text, and paths must never be committed to this repository. There is no logging, telemetry, networking, or implicit storage path.
