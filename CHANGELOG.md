# Changelog

All notable changes to BusinessCardFieldKit will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/). Before `1.0.0`, a minor release may contain breaking API or schema changes; those changes will be called out here with migration guidance.

## [Unreleased]

### Added

- An opt-in column-aware phone linker with deterministic geometry scoring and diagnostics, plus an
  independent fail-closed strict-field corrector for syntax-valid email, explicit URL, and phone
  alternatives.
- Provider-neutral vCard 3.0/4.0 parsing with UTF-8, EUC-KR, folded-line, escaped-value,
  and quoted-printable handling, plus deterministic `CardScanSession` front/back merging.
- A local `CardBackScanner` that combines back-side OCR with QR/barcode-derived vCard or URL
  suggestions. Public barcode metadata excludes the decoded payload, and no image or result is
  logged, retained, or persisted.
- A deterministic fourteen-scene card-back corpus and `--card-back-evidence` schema-3 aggregate benchmark for
  QR detection, payload-kind accuracy, back/front merge exactness, duplicate suppression, review
  decisions, card-region decisions, and latency. `card-field-private-back-benchmark` provides the same aggregate-only
  boundary for an external real-photo root with mandatory repeated measurements.
- Default-off `AppleVisionBackScanDiagnostics` with fixed source-barcode, token-recognition,
  isolated-mask, classification/merge, and total stage durations plus barcode-request counts. The
  aggregate card-back report is schema 3 and keeps its diagnostics summary optional for schema-2
  decoding.
- A default-off `AppleVisionBarcodeMaskingStrategy.projectiveSourceObservation` experiment and
  schema-1 paired benchmark. It maps source barcode quadrilaterals through a validated homography,
  falls back to exact rectified-image redetection on any unsafe geometry, and reports aggregate
  parity, signed latency deltas, isolated request savings, and fallback counts without content.
- An opt-in `--projective-mask-experiment` mode for the external private card-back runner. It
  alternates baseline and experimental scans over at least three repetitions and reuses the paired
  aggregate contract without serializing source identity, expected values, paths, or per-case data.
- A default-off `AppleVisionConditionalDualPassOptions` experiment that skips the second
  language-correction pass only for high-confidence, single-script, simple-layout scans with
  multiple complete strict-contact families and no conflicting alternatives, review warning,
  crop edge, targeted request, or full-image fallback evidence. Diagnostics schema 2 reports
  only fixed decision counts and request savings.
- An environment-gated `card-field-private-benchmark` for transient real-photo holdouts. It uses
  the shipped targeted re-recognition threshold, reads only one external corpus root, and emits
  aggregate paired metrics with deterministic case-cluster bootstrap intervals and no source
  identity or OCR content.
- A default-off, bounded source-barcode recovery experiment that performs one enhanced full-frame
  request only after an empty initial result, with paired synthetic and private aggregate evidence.

### Changed

- Reorganized the README around installation, local/privacy properties, review-first usage, and
  the verified public API; documented AnswerSheetFieldKit's provider-neutral token-layer reuse.
- Updated governance, support, security, roadmap, release, issue, and AI-contributor guidance for
  public pre-release maintenance while preserving human approval over sensitive decisions.

### Fixed

- Card-back OCR now excludes tokens substantially overlapping a barcode detected on the exact
  recognition image. Perspective-isolated cards use a second content-free barcode-region request on
  the rectified image, preventing QR modules from becoming false names or organizations while
  preserving nearby text and public metadata contracts.
- Email extraction now repairs OCR-introduced whitespace immediately around `@` while preserving
  the original reading and preventing the domain portion from also becoming a website.
- The OCR input schema now exposes `OCRToken.alternatives`, and JSON tokens without an explicit
  identifier decode with the public initializer's empty-identifier default.

## [0.1.0] - 2026-08-24

### Added

- A provider-neutral `CardFieldCore` library for deterministic OCR-to-field interpretation.
- Confidence, evidence, alternative candidates, source-token provenance, and unresolved-line reporting.
- Additive locale and industry rule packs plus host-owned personal correction stores.
- An optional Apple Vision adapter that remains separate from the core.
- Automatic foreground-card detection, bounded candidate ranking, perspective correction, and conservative full-image fallback in the Apple Vision adapter.
- `card-field-scan`, a local Apple-platform image-to-structured-JSON command with opt-in raw OCR tokens.
- Card-region selection metadata for isolated, fallback, and explicitly disabled scanning modes.
- Base rules `base-1.1.0` with conservative inline identity splitting, multilingual name variants,
  expanded title and department vocabulary, wrapped international addresses, and mixed
  email/website-line handling.
- `identityConflict` and `reviewRecommended` warnings for close competing person or organization
  candidates.
- Language-neutral JSON schemas, synthetic fixtures, and a precision/recall evaluation command.
- A contribution sanitizer that replaces source values with controlled placeholders and never uploads data.
- Privacy, architecture, contribution, security, support, and roadmap documentation.
- A DocC catalog for integrating the core as a review-first interpretation layer.
- Review-first CRM integration guidance and private, transient real-image validation that never places images or PII in the public repository.
- Local image-enhancement pipeline in the Apple Vision adapter: configurable upscaling to a
  minimum long edge, grayscale conversion, contrast adjustment, and unsharp-mask sharpening
  (`AppleVisionPreprocessingConfiguration`, `--no-preprocess`).
- Dual-pass recognition that reads each region with and without Vision language correction and
  merges readings geometrically; emails, phone numbers, and URLs keep the raw text while prose
  keeps corrected text (`--no-dual-pass`).
- Multi-candidate OCR: ranked Vision readings beyond the first survive as `OCRToken.alternatives`
  for host-side review and fuzzy matching.
- Targeted re-recognition of low-confidence lines from an upscaled source crop, replacing a
  reading only when the second pass is stronger (`--no-re-recognize`).
- Script-based token language inference in `CardFieldCore`
  (`TokenLanguageInference`) plus adapter wiring, giving tokens best-effort BCP 47 tags when no
  host hint exists (`--no-language-inference`).
- Deterministic layout utilities in `CardFieldCore`: `LayoutAnalyzer` groups tokens into visual
  rows and column runs for multi-column card layouts.
- Attention-saliency fallback that proposes one card-shaped candidate when rectangle detection
  finds nothing, still gated by contact-text evidence.
- Enforced minimum output resolution for perspective-corrected cards before OCR.
- Pinned `VNRecognizeTextRequest` revision for cross-OS recognition stability.
- Synchronous and async image scanning plus reusable `scanTokens` APIs for non-card documents.
- End-to-end synthetic-image tests that render card fronts with Core Text and assert classified
  fields through the complete scan pipeline.

### Changed

- The Apple Vision scanner reuses a process-wide `CIContext` instead of creating one per scan.
- Card-region evidence regexes are precompiled Swift Regex values instead of per-call ICU strings.

### Fixed

- All Sources, Tests, and Package.swift files conform to strict `swift format lint` after the OCR
  pipeline changes; formatting-only changes have no behavioral effect.

### Tests

- Added a regression test pinning `recognitionRevision` clamping to `1...3`.
- Synthetic-fixture tests use fictional domains only (`example.com`, `example.net`,
  `example.org`); no real provider domains appear in test data.

[Unreleased]: https://github.com/megabrain11/BusinessCardFieldKit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/megabrain11/BusinessCardFieldKit/tree/v0.1.0
