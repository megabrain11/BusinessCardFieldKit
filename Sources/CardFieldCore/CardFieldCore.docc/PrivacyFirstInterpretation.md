# Build a Privacy-First Field Interpretation Pipeline

Convert OCR output into reviewable contact-field suggestions while keeping images, personal data, and CRM intelligence under host control.

## Create provider-neutral tokens

Convert each OCR observation on the upright card front into an ``OCRToken``. Bounding boxes use a normalized unit square with a bottom-left origin. Providers that use a top-left origin must convert `y` with `1 - top - height`.

```swift
import CardFieldCore

let tokens = [
  OCRToken(
    id: "line-1",
    text: "Alex Kim",
    boundingBox: .init(x: 0.10, y: 0.75, width: 0.35, height: 0.08),
    confidence: 0.97,
    language: "en"
  )
]
```

Do not send images to the core. A provider adapter should only translate observation text, confidence, language, identifiers, and geometry.

## Interpret suggestions

Pass the complete set of front-side tokens to ``CardFieldClassifier/classify(_:)``:

```swift
let classifier = CardFieldClassifier()
let result = try classifier.classify(tokens)

if let suggestion = result.fullName {
  print(suggestion.normalizedValue)
  print(suggestion.confidence)
  print(suggestion.evidence)
}
```

A ``ClassifiedValue`` preserves the original and normalized values, confidence, evidence, alternative candidates, and source-token identifiers. Use ``CardFieldResult/warnings`` and ``CardFieldResult/unclassifiedLines`` to surface uncertainty instead of silently inventing certainty.

## Add context without collecting contacts

Use ``RulePack`` for general locale or industry vocabulary. Use a host-provided ``CorrectionStore`` for narrow personal patterns, such as an organization associated with an email domain. Keep corrections local and avoid encoding complete contact records.

Rules are applied deterministically in this order:

1. Built-in base rules
2. Locale and industry packs
3. Personal corrections

Pin rule-pack and package versions when reproducibility matters.

## Keep the CRM boundary explicit

The reusable layer owns field contracts, deterministic classification, explanation, and synthetic conformance tests. A host such as Relationship Memory owns real scans and OCR, review UI, approved contact values, identity matching, deduplication, synchronization, relationship notes, and recommendations.

Begin a migration in shadow mode: run the existing parser and `CardFieldCore` together, compare their suggestions locally, and measure field-specific corrections before changing what the CRM saves. Never auto-merge identities from a business-card suggestion.

## Share only reviewed structure

If a failure pattern may help the community, create a draft with ``ContributionSanitizer`` and inspect it before sharing. The sanitizer replaces values with controlled placeholders and does not upload anything. Do not contribute real images, OCR text, contact values, or personal correction files.
