# Changelog

All notable changes to BusinessCardFieldKit will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/). Before `1.0.0`, a minor release may contain breaking API or schema changes; those changes will be called out here with migration guidance.

## [Unreleased]

### Added

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
- Async scanning APIs (`scanAsync(imageData:)`, `scanAsync(cgImage:)`) that run the local pipeline
  off the calling actor.
- End-to-end synthetic-image tests that render card fronts with Core Text and assert classified
  fields through the complete scan pipeline.

### Changed

- The Apple Vision scanner reuses a process-wide `CIContext` instead of creating one per scan.
- Card-region evidence regexes are precompiled Swift Regex values instead of per-call ICU strings.

### Fixed

- All Sources, Tests, and Package.swift files conform to strict `swift format lint` again after
  the OCR pipeline changes; formatting-only changes with no behavioral diff.

### Tests

- Added a regression test pinning `recognitionRevision` clamping to `1...3`.
- New synthetic-fixture tests use fictional domains only (`example.com`, `example.net`,
  `example.org`); no real provider domains appear in test data.

### Added (earlier)

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

No release tags have been published yet.
