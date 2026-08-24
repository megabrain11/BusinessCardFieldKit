# Architecture

## Boundaries

`CardFieldCore` begins after front-side OCR and ends with field suggestions. It never receives images, persists cards, resolves identities, writes contacts, or performs network operations. The optional `AppleVisionAdapter` accepts an image for the duration of a synchronous local recognition call, isolates and perspective-corrects one likely foreground card when evidence supports it, then passes provider-neutral tokens into the core. It does not capture, retain, or persist that image.

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
```

## Modules

### CardFieldCore

The core defines provider-neutral contracts, OCR normalization, typed extraction, candidate ranking, confidence, evidence, additive rule packs, correction overlays, and contribution sanitization. It also exposes two provider-neutral utilities: `LayoutAnalyzer` groups tokens into deterministic visual rows and columns for hosts reasoning about multi-column cards, and `TokenLanguageInference` labels tokens with a best-effort BCP 47 tag derived from Unicode script ranges. Foundation is used for Unicode, regular expressions, coding, locks, and optional local JSON reads. There is no implicit file access: only a host-created `LocalJSONCorrectionStore` reads its explicit URL.

### AppleVisionAdapter

The optional adapter validates encoded image data and resolves explicit or EXIF orientation. The scan pipeline then runs entirely on one upright working image:

1. Local Core Image enhancement upscales small sources to a configured long edge and applies grayscale, contrast, and unsharp-mask stages (`AppleVisionPreprocessingConfiguration`).
2. A `VNRecognizeTextRequest` pinned to a configured revision reads each region. When dual-pass mode is enabled, a second request with the opposite language-correction flag runs as well; readings merge geometrically so emails, phone numbers, and URLs keep the raw text while prose keeps corrected text. Up to `candidateCount` Vision readings per line survive as `OCRToken.alternatives`.
3. Lines at or below the targeted-re-recognition confidence limit are re-read from an upscaled crop of their source region and replaced only when the second reading is stronger.
4. Tokens without a host language hint receive script-based tags from `TokenLanguageInference`.

By default, the adapter first asks Vision for a bounded set of plausible card quadrilaterals, ranks them using geometry plus contact-text evidence, perspective-corrects the strongest candidates to a minimum output resolution, and recognizes each selected region. When rectangle detection finds nothing and saliency fallback is enabled, attention-based saliency proposes one card-shaped candidate subject to the same evidence gate. When no candidate clears that gate, the adapter recognizes the complete upright image instead. The result reports whether selection was `isolated`, `fullImageFallback`, or `disabled`, including source-image region metadata for an isolated card.

Synchronous `scan` methods and async `scanAsync` variants run the same local path; async forms execute on a background task so callers never block an actor. The same pipeline is also exposed as `scanTokens` / `scanTokensAsync`, a generic token-only entry point that stops before classification so non-card documents can reuse local OCR without business-card heuristics influencing their results; hosts own any downstream interpretation of those tokens. The target contains all Apple Vision, Core Image, ImageIO, and Core Graphics imports. A process-wide shared `CIContext` keeps batch scans affordable. The adapter does not access a camera, retain an image, persist output, or use the network. Existing Vision observations can still be converted without running another request.

### card-field-scan

The Apple-platform CLI exercises the adapter without adding storage behavior. It reads only paths explicitly supplied by the caller and writes JSON to standard output. Structured fields are the default; raw OCR tokens require `--include-tokens`. Pipeline stages can be disabled individually (`--no-preprocess`, `--no-dual-pass`, `--no-re-recognize`, `--no-language-inference`). The scanner isolates one card rather than enumerating every card in a scene. See [Local Image Scanning](Docs/IMAGE_SCANNING.md).

### CardFieldEvaluation

The evaluation module compares normalized field values in synthetic fixtures. For each field it reports true positives, false positives, false negatives, precision, and recall. The CLI prints a JSON report and performs no upload.

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

Every field contains its normalized and original value, confidence, evidence, alternatives, and source token identifiers. A host must treat the output as an editable suggestion. The classifier intentionally returns unresolved identity when evidence is weak. Contact persistence, identity matching, automatic merging, and relationship intelligence remain host-owned CRM decisions.

## Compatibility

Contracts and rule packs carry explicit versions. Additive optional fields are preferred for compatible changes. Removing or changing semantics requires a new major contract version. JSON schemas under `Schemas/` are the language-neutral reference.

## Security and data flow

The library does not log source text, transmit data, retain images, or include telemetry. Apple Vision recognition is local to the calling device. Real business-card photos and their OCR or PII are limited to private, transient local validation and are never committed to the public repository. Sanitization converts every token to a controlled placeholder and buckets OCR confidence. Original text and personal correction values are excluded from contribution drafts. Sharing the draft remains an explicit host or user action.
