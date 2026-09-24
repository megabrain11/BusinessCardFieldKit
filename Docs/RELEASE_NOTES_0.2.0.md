# BusinessCardFieldKit v0.2.0 — Privacy-first local OCR and field extraction

These notes accompany the `v0.2.0` tag.

## Highlights

- Privacy-first, provider-neutral `CardFieldCore` contracts and deterministic field suggestions
  with confidence, evidence, alternatives, warnings, and source-token provenance.
- A complete local Apple Vision front-card pipeline with card isolation, perspective correction,
  image enhancement, multilingual hints, dual-pass recognition, targeted re-recognition, and a
  reusable token-only path for non-card documents.
- Conservative opt-in column-aware phone linking and strict syntax correction for email, explicit
  URL, and phone alternatives.
- Optional local card-back barcode recognition, vCard 3.0/4.0 parsing, QR-region OCR masking, and
  deterministic same-card front/back suggestion merging.
- Deterministic fictional corpora, field-level evaluation, aggregate-only OCR/card-back benchmarks,
  and external private-holdout runners that do not serialize source identity or OCR content.
- Privacy-safe diagnostics and fail-closed OCR/barcode experiments that remain disabled by default.

## Supported toolchain and platforms

- Swift tools 6.0 or later
- macOS 13 or later
- iOS 17 or later
- `CardFieldCore` for provider-neutral interpretation
- `AppleVisionAdapter` for local Apple Vision and barcode recognition

## Privacy properties

The package contains no networking or telemetry. It does not access a camera, write contacts,
persist images, or automatically store OCR results. The image pipeline runs only on images
explicitly supplied by a host; decoded barcode payloads are not logged or persisted. Public
fixtures are fictional, and private-photo evaluation stays outside the repository and emits
aggregate-only evidence.

## Validation status

The release tree passed the `Scripts/check-repository.sh` steps on 2026-09-25 with Swift 6.3.3 and
Xcode 26.6 on macOS: 202 tests, both synthetic field-evaluation corpora, CLI smoke tests,
deterministic OCR/card-back benchmark paths, strict formatting, DocC warnings-as-errors, JSON syntax
validation, and the credential scan. GitHub Actions runs the same script on the `macos-26` runner
for every pull request and on `main`.

## Known limitations

- This remains pre-`1.0` software. Public Swift APIs, schemas, and rule behavior may change in a
  minor release with changelog and migration notes.
- Apple Vision output can vary by OS, hardware, print quality, lighting, crop, and orientation.
  Golden-scene and barcode-evidence expectations are calibrated on macOS 26 Vision; on macOS 15
  Vision, phone numbers differed in five of the fifty golden scenes, all degraded variants.
- Automatic isolation selects one likely card; it does not enumerate multiple cards in a scene.
- Multilingual coverage and fictional evaluation breadth are intentionally incomplete.
- Experimental conditional dual-pass, projective barcode masking, and empty-result barcode
  recovery paths are not production recommendations and remain off by default.
- The package provides suggestions, not verified identity facts. Hosts must review before saving,
  merging, or acting on a field.
- Shadow-mode integration guidance, local quality measures, adapter conformance fixtures, and
  explicit migrations were planned for this release and moved to `0.3.0`; see the roadmap.

## Compatibility expectations

Changes since `v0.1.0` are primarily additive, including new products, result metadata, optional
configuration, and benchmark tooling. Pre-`1.0` consumers should still review the changelog and pin
versions when reproducibility matters. The provider-neutral contract remains versioned, and new
decoding fields use backward-compatible defaults where applicable.
