# Architecture

## Boundaries

`CardFieldCore` begins after front-side OCR and ends with field suggestions. It never receives images, persists cards, resolves identities, writes contacts, or performs network operations. The optional `AppleVisionAdapter` accepts an image for the duration of a synchronous local recognition call, then passes provider-neutral tokens into the core. It does not capture, retain, or persist that image.

```text
Host capture -> AppleVisionScanner (local OCR) --+
                                                 +-> [OCRToken] -> CardFieldCore -> CardFieldResult
Other OCR provider -> provider adapter ----------+                    |   |   |
                                                                     base pack personal
                                                                     rules rules corrections
                                                                               |
                                                                               v
                                                               contribution sanitizer

Synthetic fixtures -> CardFieldEvaluation -> precision/recall report
```

## Modules

### CardFieldCore

The core defines provider-neutral contracts, OCR normalization, typed extraction, candidate ranking, confidence, evidence, additive rule packs, correction overlays, and contribution sanitization. Foundation is used for Unicode, regular expressions, coding, locks, and optional local JSON reads. There is no implicit file access: only a host-created `LocalJSONCorrectionStore` reads its explicit URL.

### AppleVisionAdapter

The optional adapter validates encoded image data, resolves explicit or EXIF orientation, runs `VNRecognizeTextRequest`, converts `VNRecognizedTextObservation` values to `OCRToken`, and invokes a host-configurable `CardFieldClassifier`. The target contains all Apple Vision, ImageIO, and Core Graphics imports. It does not access a camera, retain an image, persist output, or use the network. Existing Vision observations can still be converted without running another request.

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

The same token input, package version, rule-pack versions, and correction set therefore produce the same core result. Image-to-text output from Apple Vision may differ across operating-system and Vision revisions; that provider behavior is outside the core determinism guarantee.

## Rule layers

Base rules contain broadly useful conservative vocabulary. Locale and industry packs add terms without replacing executable behavior. Personal corrections apply last and can map domains, aliases, preferred ordering, title vocabulary, phone labels, or exact recurring patterns.

Arbitrary executable scripts are not supported. This keeps packs portable, inspectable, and deterministic.

## Confidence and evidence

Syntax-specific fields receive confidence from OCR quality plus structural validation. Identity fields combine conservative syntax, OCR confidence, layout prominence, nearby titles, and email-local-part overlap. Organizations use suffixes, institution vocabulary, uppercase or numeric brand shape, and email-domain hints.

Every field contains its normalized and original value, confidence, evidence, alternatives, and source token identifiers. A host must treat the output as an editable suggestion. The classifier intentionally returns unresolved identity when evidence is weak.

## Compatibility

Contracts and rule packs carry explicit versions. Additive optional fields are preferred for compatible changes. Removing or changing semantics requires a new major contract version. JSON schemas under `Schemas/` are the language-neutral reference.

## Security and data flow

The library does not log source text, transmit data, retain images, or include telemetry. Apple Vision recognition is local to the calling device. Sanitization converts every token to a controlled placeholder and buckets OCR confidence. Original text and personal correction values are excluded from contribution drafts. Sharing the draft remains an explicit host or user action.
