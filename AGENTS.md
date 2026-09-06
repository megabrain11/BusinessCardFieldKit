# AGENTS.md

Guidance for AI coding agents (Codex, Claude Code, and others) working in this repository.

## What this project is

BusinessCardFieldKit is a privacy-first Swift Package that turns business-card OCR output into structured, reviewable field suggestions. It is an *interpretation layer*, not a product:

- `CardFieldCore` — provider-neutral contracts, normalization, rules, classification. **No image, Vision, UIKit, networking, or storage dependencies.**
- `AppleVisionAdapter` — optional local Apple Vision pipeline (enhancement → card isolation → OCR → classification). The only target allowed to import Vision/CoreImage/CoreGraphics/ImageIO.
- `CardFieldEvaluation` + `card-field-eval` — synthetic fixture precision/recall.
- `card-field-scan` — local Apple-platform CLI emitting JSON to stdout.
- `AppleVisionBenchmarking` + benchmark CLIs — deterministic synthetic rendering and aggregate-only OCR, card-back barcode/merge, and latency comparisons.

Out of scope forever: contact databases, identity resolution/merging, relationship graphs, telemetry, networking, camera access, image persistence.

## Hard rules

1. **Never commit real PII**: real card photos, OCR dumps of real cards, real names/emails/phones/addresses. Fixtures must be fictional (`example.com`, `555` phone numbers). See PRIVACY.md.
2. **Keep the core provider-neutral.** If code needs an image or Vision type, it belongs in `AppleVisionAdapter`, never in `CardFieldCore`.
3. **Determinism**: no clock, randomness, locale-global state, or network in classification paths. Same tokens + package version + rule packs ⇒ same result. Sort everything stably.
4. **Additive changes preferred.** Contracts carry versions (`contractVersion`, `schemaVersion`). New fields need backward-compatible decoding (`decodeIfPresent` with defaults) — see `OCRToken.alternatives` for the pattern.
5. **Suggestions, not facts.** Never auto-confirm; weak evidence stays unresolved by design.
6. **No comments unless required**; when needed, explain *why* briefly. Public API gets doc comments (match existing style).

## Build & verify

```sh
swift build                 # compile
swift test --no-parallel   # all tests must pass
swift run card-field-eval Fixtures/Synthetic/public-alpha.json   # fixture eval
swift run card-field-scan --help                            # CLI smoke test
swift run card-field-benchmark --help                       # benchmark CLI smoke test
swift run card-field-private-benchmark --help               # private holdout smoke test
swift run card-field-private-back-benchmark --help          # private card-back smoke test
```

`Scripts/check-repository.sh` additionally requires [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) for its credential scan and fails fast when it is missing.

- Swift tools 6.0 (strict concurrency ON), platforms macOS 13+ / iOS 17+.
- Tests run on macOS only for adapter targets; core tests are cross-platform.
- Vision-dependent E2E tests render synthetic cards with Core Text — keep fixtures fictional and deterministic.

## Architecture map

```
Sources/
  CardFieldCore/
    Contracts.swift          OCRToken, ClassifiedValue, CardFieldResult, warnings
    Normalization.swift      whitespace/NFC cleanup + reading-order sort
    LanguageInference.swift  TokenLanguageInference (script → BCP-47 tag)
    LayoutAnalyzer.swift     visual row/column grouping (geometry-only)
    ColumnAwareClassifier.swift optional phone label-value linking and diagnostics
    StrictFieldCorrection.swift optional syntax-only OCR alternative selection
    BackScan.swift            vCard parsing + same-card front/back result merge
    Rules.swift              RulePack vocabularies, base rules
    CardFieldClassifier.swift  the whole rule-based classifier (~1200 lines)
    Corrections.swift        local personal correction store protocol
    ContributionSanitizer.swift  placeholder-based draft sanitizer
  AppleVisionAdapter/
    AppleVisionAdapter.swift configs, scanner, region selection, evidence, token mapping
    BarcodeMaskingExperiment.swift opt-in exact projective source-observation masking with fail-closed fallback
    ConditionalDualPass.swift default-off, fail-closed second-request experiment
    ImagePreprocessing.swift upscale/grayscale/contrast/sharpen pipeline + shared CIContext
    ScanDiagnostics.swift opt-in redacted stage timings and Vision request counters
    CardBackDiagnostics.swift opt-in content-free back-scan timings and barcode request counters
    CardBackScanner.swift local barcode detection + back-side OCR composition
    BarcodeDetectionRecovery.swift default-off, one-request empty-result recovery experiment
  AppleVisionBenchmarking/
    GoldenCorpus.swift deterministic 25-layout × 2-variant renderer and expectations
    DiagnosticsBenchmark.swift aggregate-only latency/request benchmark contract
    TargetedReRecognitionBenchmark.swift paired targeted-stage evidence report
    PrivateHoldoutBenchmark.swift external-only aggregate private evaluator
    CardBackBenchmark.swift deterministic card-back scenes and aggregate report
    ProjectiveBarcodeMaskingBenchmark.swift paired request/latency/parity report for the opt-in mask experiment
    BarcodeDetectionRecoveryBenchmark.swift paired aggregate QR stress and recovery evidence
    PrivateCardBackBenchmark.swift external-only aggregate private back and paired mask evaluator
  card-field-scan/main.swift CLI flags mirror scan configuration
  card-field-benchmark/main.swift synthetic diagnostics benchmark CLI
  card-field-private-benchmark/main.swift environment-gated private benchmark CLI
  card-field-private-back-benchmark/main.swift private back benchmark CLI
Tests/
  CardFieldCoreTests/        classifier, fixtures, layout, language, encoding
  AppleVisionAdapterTests/   geometry, merging, preprocessing, E2E rendered cards, golden-scene regression corpus (Fixtures/GoldenScenes)
Docs/, Schemas/, Rules/, Fixtures/, Examples/
```

## Key design decisions (do not undo casually)

- **Dual-pass OCR** (corrected + uncorrected) merges geometrically; strict-syntax text (email/phone/URL — see `prefersUncorrectedText`) always keeps the raw reading because language correction rewrites proper nouns and addresses.
- **Targeted re-recognition never fails a scan**: any error returns original tokens.
- **Saliency fallback** candidates are capped at 0.75 confidence so real rectangle observations win ties, and still require the contact-text evidence gate.
- **Shared CIContext** is `nonisolated(unsafe)` — Apple documents `CIContext` as thread-safe; recreating per scan dominates batch latency. Same escape hatch applies to precompiled regex statics.
- **`OCRToken.alternatives`** decodes legacy JSON missing the key as `[]`; the default classifier consumes only `text`. The opt-in strict-field corrector may select one alternative only for email, explicit URL, or phone syntax under the fail-closed rules documented in `ARCHITECTURE.md`.
- **Conditional dual-pass remains experimental and default OFF.** Full-image fallback, targeted recognition, weak or mixed-script text, complex/cropped layouts, strict alternative conflicts, and review warnings must retain the existing second request. Synthetic parity cannot promote it without the private holdout.
- **Card-back evidence stays aggregate-only.** Never serialize decoded payloads, OCR content, private image references, tags, or case identifiers. Synthetic back success cannot replace private physical-device acceptance.
- **Projective barcode masking remains experimental and default OFF.** The baseline re-detects
  barcode regions on the exact rectified image. The opt-in strategy maps source observation
  quadrilaterals through a validated homography and falls back to that baseline on any invalid,
  degenerate, or out-of-range mapping; it must not approximate a bounding box from weak geometry.
- **Private projective comparison remains aggregate-only and opt-in.** Require at least three
  measured repetitions, alternate strategy order deterministically, preserve a redacted skip for a
  missing root, and never serialize expected values, source identity, paths, or per-case outcomes.
- **Source barcode recovery remains experimental and default OFF.** It may run one enhanced
  full-frame request only after the initial source request returns no observations. Successful
  initial detection never pays the retry; preprocessing or retry failure preserves the empty
  baseline result. Promotion requires private physical-device evidence, not synthetic improvement.

## Current status / open work

See `Docs/AI_COLLABORATION.md` for the latest handoff notes, completed OCR upgrades, and prioritized next steps. Update it when you finish significant work.

## Commit style

Short imperative subject ("Add saliency fallback for card isolation"). No secrets, no generated artifacts (`.build/` is ignored).
