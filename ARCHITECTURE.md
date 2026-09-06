# Architecture

## Boundaries

`CardFieldCore` begins after OCR or barcode decoding and ends with field suggestions. It never receives images, persists cards, resolves identities across contacts, writes contacts, or performs network operations. The optional `AppleVisionAdapter` accepts an image for the duration of a synchronous local recognition call, isolates and perspective-corrects one likely foreground card when evidence supports it, then passes provider-neutral tokens into the core. Its optional back scanner also detects barcode payloads locally. It does not capture, retain, or persist either image.

```text
Host capture -> card-region detection -> accepted: perspective-corrected card --+
                                  \-> conservative fallback: full upright image --+
                                                                                  v
                                                    AppleVisionScanner (local OCR) --+
Other OCR provider -> provider adapter ------------------------------------------+-> [OCRToken]
                                                                                       |
                                                                                       v
                                                                         CardFieldCore -> CardFieldResult
                                                                          |   |   |
                                                                         base pack personal
                                                                         rules rules corrections
                                                                                   |
                                                                                   v
                                                                   contribution sanitizer

Synthetic fixtures -> CardFieldEvaluation -> precision/recall report
Synthetic image manifest -> AppleVisionBenchmarking -> aggregate diagnostics report
External private root -> AppleVisionBenchmarking -> aggregate-only holdout report
Synthetic card-back manifest -> AppleVisionBenchmarking -> aggregate barcode/merge report
External private card-back root -> AppleVisionBenchmarking -> aggregate-only back report

Card-back barcode -> local payload decoding -> VCardParser -> CardFieldResult --+
Front result + optional back result -> CardScanSession -> MergedCardResult
```

## Modules

### CardFieldCore

The core defines provider-neutral contracts, OCR normalization, typed extraction, candidate ranking, confidence, evidence, additive rule packs, correction overlays, and contribution sanitization. It also exposes `VCardParser` for vCard 3.0/4.0 text or UTF-8/EUC-KR bytes and `CardScanSession` for deterministic same-card front/back combination. Barcode-origin duplicates outrank OCR readings, while conflicting singular identity values retain the losing value as an alternative and require review. This is not cross-contact identity resolution. `LayoutAnalyzer` groups tokens into deterministic visual rows and columns, and `TokenLanguageInference` labels tokens with a best-effort BCP 47 tag derived from Unicode script ranges. Foundation is used for Unicode, regular expressions, coding, locks, and optional local JSON reads. There is no implicit file access: only a host-created `LocalJSONCorrectionStore` reads its explicit URL.

### AppleVisionAdapter

The optional adapter validates encoded image data and resolves explicit or EXIF orientation. The scan pipeline then runs entirely on one upright working image:

1. Local Core Image enhancement upscales small sources to a configured long edge and applies grayscale, contrast, and unsharp-mask stages (`AppleVisionPreprocessingConfiguration`).
2. A `VNRecognizeTextRequest` pinned to a configured revision reads each region. When dual-pass mode is enabled, a second request with the opposite language-correction flag runs as well; readings merge geometrically so emails, phone numbers, and URLs keep the raw text while prose keeps corrected text. Up to `candidateCount` Vision readings per line survive as `OCRToken.alternatives`.
3. Lines at or below the targeted-re-recognition confidence limit are re-read from an upscaled crop of their source region and replaced only when the second reading is stronger.
4. Tokens without a host language hint receive script-based tags from `TokenLanguageInference`.

By default, the adapter first asks Vision for a bounded set of plausible card quadrilaterals, ranks them using geometry plus contact-text evidence, perspective-corrects the strongest candidates to a minimum output resolution, and recognizes each selected region. When rectangle detection finds nothing and saliency fallback is enabled, attention-based saliency proposes one card-shaped candidate subject to the same evidence gate. When no candidate clears that gate, the adapter recognizes the complete upright image instead. The result reports whether selection was `isolated`, `fullImageFallback`, or `disabled`, including source-image region metadata for an isolated card.

Synchronous `scan` methods and async `scanAsync` variants run the same local path; async forms execute on a background task so callers never block an actor. The same pipeline is also exposed as `scanTokens` / `scanTokensAsync`, a generic token-only entry point that stops before classification so non-card documents can reuse local OCR without business-card heuristics influencing their results; hosts own any downstream interpretation of those tokens. The target contains all Apple Vision, Core Image, ImageIO, and Core Graphics imports. A process-wide shared `CIContext` keeps batch scans affordable. The adapter does not access a camera, retain an image, persist output, or use the network. Existing Vision observations can still be converted without running another request.

`CardBackScanner` runs the same text pipeline and a local `VNDetectBarcodesRequest`. vCard and explicit HTTP(S) payloads become structured suggestions; unsupported payloads expose only content-free symbology, kind, and geometry metadata. A QR-only back is valid even when OCR finds no text. The token pipeline internally exposes the exact upright recognition image for the duration of the call. When a card is perspective-isolated, the back scanner detects masking regions again on that rectified image; otherwise it reuses source-image regions. OCR tokens substantially overlapping those same-coordinate regions are removed before classification, so QR modules cannot become false names or organizations without approximating a source-to-card transform. The public token and barcode metadata contracts remain unchanged, and the recognition image is never retained or returned. `CardScanSession` can then combine the fields with the separately scanned front.

The shared diagnostics option also controls an optional `AppleVisionBackScanDiagnostics` result. It
reports only fixed stage durations and source/masking barcode-request counts. The outer timer begins
after encoded image decoding, and the nested token scanner runs with its own diagnostics disabled to
avoid double measurement. Diagnostics never contain decoded payloads, OCR content, confidence,
geometry, images, paths, or token values, and enabling them cannot change scan fields.

`AppleVisionScanConfiguration.diagnostics` can opt a caller into aggregate stage timings, Vision request counts, and execution flags on either result type. The default is disabled and creates no instrumentation object. The report has a versioned, Codable, fixed-field contract and deliberately excludes OCR text, token values and confidence, geometry, image data, and paths. Repeated recognition requests accumulate under stable stage identifiers; nested targeted re-recognition time can overlap primary/secondary recognition time, so stage durations are diagnostic spans rather than additive accounting. Enabling diagnostics cannot select a different recognition path.

### card-field-scan

The Apple-platform CLI exercises the adapter without adding storage behavior. It reads only paths explicitly supplied by the caller and writes JSON to standard output. Structured fields are the default; raw OCR tokens require `--include-tokens`. Pipeline stages can be disabled individually (`--no-preprocess`, `--no-dual-pass`, `--no-re-recognize`, `--no-language-inference`). The scanner isolates one card rather than enumerating every card in a scene. See [Local Image Scanning](Docs/IMAGE_SCANNING.md).

### CardFieldEvaluation

The evaluation module compares normalized field values in synthetic fixtures. For each field it reports true positives, false positives, false negatives, precision, and recall. The CLI prints a JSON report and performs no upload.

### AppleVisionBenchmarking

The Apple-platform benchmark module expands a versioned manifest into 25 layouts with two deterministic Core Text/Core Graphics variants each. It compares the shipped pipeline against three disabled-stage configurations while consuming only the redacted diagnostics contract and expected-field mismatch counts. A separately versioned 12-layout × 2-variant stress corpus supports a paired targeted re-recognition enabled/disabled report with field-family exactness, false clears, review changes, recoveries, regressions, requests, and duration distributions. An independent environment-gated runner may read a manifest and images from one external private root, but it emits only aggregate paired metrics and never serializes source identity. Private input cannot configure the shipped confidence limit.

The same module owns a separate fourteen-scene card-back corpus with deterministic QR rendering for vCard 3.0/4.0, URLs, unsupported payloads, geometric and contrast stress, multiple codes, visible text, duplicate suppression, conflict review, and two whole-card perspective-isolation cases. Its schema-3 aggregate report measures barcode count, payload-kind accuracy, back and merged exactness, duplicate freedom, review decisions, card-region decisions, total latency, content-free stage timing, and barcode-request distributions without decoded content or case identity. The diagnostics summary is optional so schema-2 reports continue to decode. `card-field-private-back-benchmark` accepts only relative regular files beneath one external root, requires three measured repetitions, strips private tags and corpus identity, and emits a redacted skip when no root is configured. Synthetic and private aggregate results are evidence inputs, never automatic release decisions.

All benchmark CLIs separate warmup and measured runs and never serialize OCR text, tokens, confidence, images, paths, or case identifiers. Benchmark configurations cannot change the scanner's shipped defaults.

## Determinism

- Missing token identifiers become stable positional identifiers after reading-order normalization.
- Reading order uses normalized geometry with identifier tie-breaking.
- Rule packs are ordered by priority then identifier.
- Personal corrections are ordered by identifier.
- Candidate ties use source position then normalized value.
- Evidence and warnings use stable lexical ordering.
- No clock, randomness, model service, locale-global state, or network response affects classification.

The same token input, package version, rule-pack versions, and correction set therefore produce the same core result. Image-to-text output from Apple Vision may differ across operating-system and Vision revisions; the adapter pins the text-recognition revision by default to reduce that variance, but provider-level behavior remains outside the core determinism guarantee.

## Rule layers

Base rules contain broadly useful conservative vocabulary. Locale and industry packs add terms without replacing executable behavior. Personal corrections apply last and can map domains, aliases, preferred ordering, title vocabulary, phone labels, or exact recurring patterns.

Arbitrary executable scripts are not supported. This keeps packs portable, inspectable, and deterministic.

## Confidence and evidence

Syntax-specific fields receive confidence from OCR quality plus structural validation. Identity fields combine conservative syntax, OCR confidence, layout prominence, nearby titles, and email-local-part overlap. Organizations use suffixes, institution vocabulary, uppercase or numeric brand shape, and email-domain hints.

Email extraction may remove OCR-introduced whitespace immediately around `@` only when the resulting reading already satisfies complete email syntax. The compact value is normalized while the spaced OCR reading remains `originalValue`; the same domain span is excluded from website extraction. This repair does not join prose lacking a dotted domain and does not alter free-text tokens.

`AppleVisionConditionalDualPassOptions` is an independent, disabled-by-default experiment inside an otherwise configured accurate dual-pass scan. It may retain the corrected primary reading without issuing the opposite language-correction request only when at least two strict-contact families are complete, every line clears the confidence floor, the content is single-script Latin and single-column, no text touches the crop boundary, alternatives do not introduce another valid contact or country-code form, and base classification does not recommend review. Full-image fallback and targeted re-recognition always retain dual-pass. Rejection is the safe outcome: the existing second request and merge run unchanged. The experiment does not alter `CardFieldCore`, scanner defaults, or free-text classification.

Diagnostics schema 2 adds only a fixed reason/count list, the conditional-policy configured flag, and a skip count. It never serializes the reading that triggered a decision. The synthetic benchmark interleaves shipped and conditional scans per scene and reports paired exact/review changes, second-request totals, and p50/p95 deltas; this evidence cannot promote the option without a private real-photo holdout.

An optional, disabled-by-default column-aware pass can recover mobile, work, and fax values when a standalone label and its number are separated by OCR reading order. It consumes the provider-neutral row and column groups from `LayoutAnalyzer`, adds only previously unresolved values, fails closed on weak geometry, and returns per-call diagnostics through `classifyWithDiagnostics`. Other field families remain on the legacy classifier until they have independent evidence and regression coverage.

An independent `StrictFieldCorrectionOptions` pass can opt in to syntax-validated `OCRToken.alternatives` for email, explicitly prefixed website, and phone lines. The primary reading is never replaced when it is already valid. An alternative is selected only when it is the sole normalized valid value, exceeds the primary syntax score by at least `0.30`, and the observation confidence is at least `0.55`. Duplicate renderings of one normalized value collapse deterministically. Multiple valid values, local-versus-international phone conflicts, insufficient score margin, and low confidence retain the original and recommend review; a phone alternative must preserve the printed mobile, work, or fax label. Invalid alternatives are ignored. Name, title, organization, department, and address classification always consume the original token text and legacy contact-consumption state, so enabling strict-field correction cannot use alternative text as identity evidence.

Every field contains its normalized and original value, confidence, evidence, alternatives, and source token identifiers. A host must treat the output as an editable suggestion. The classifier intentionally returns unresolved identity when evidence is weak. Contact persistence, identity matching, automatic merging, and relationship intelligence remain host-owned CRM decisions.

## Compatibility

Contracts and rule packs carry explicit versions. Additive optional fields are preferred for compatible changes. Removing or changing semantics requires a new major contract version. JSON schemas under `Schemas/` are the language-neutral reference.

## Security and data flow

The library does not log source text, transmit data, retain images, or include telemetry. Apple Vision recognition is local to the calling device. Real business-card photos and their OCR or PII are limited to private, transient local validation and are never committed to the public repository. Sanitization converts every token to a controlled placeholder and buckets OCR confidence. Original text and personal correction values are excluded from contribution drafts. Sharing the draft remains an explicit host or user action.
