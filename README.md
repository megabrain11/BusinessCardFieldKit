# BusinessCardFieldKit

BusinessCardFieldKit is a privacy-first, explainable engine for normalizing front-side business-card OCR and classifying text into structured fields. It is not a contact database, identity service, CRM, image store, or relationship product.

Phase 1 is a pure Swift Package. `CardFieldCore` has no dependency on UIKit, SwiftUI, Vision, image types, file storage, or networking. Hosts may supply provider-neutral OCR observations directly. On Apple platforms, the optional `AppleVisionAdapter` can also recognize a front-image `Data` or `CGImage` locally and pass its observations to the core. Hosts still decide how to capture images, review suggestions, persist approved values, and handle an optional back image.

## Highlights

- Deterministic classification with confidence, alternatives, evidence, and source token identifiers
- Conservative multilingual name handling for Korean, Latin, CJK, and mixed layouts
- Typed phone numbers, email addresses, websites, profiles, social handles, organizations, titles, departments, and addresses
- Three explicit rule layers: base rules, locale or industry packs, then local personal corrections
- Local-only correction-store protocol with memory and JSON implementations
- Sanitized structural contribution drafts with no automatic upload
- Language-neutral JSON contracts and rule-pack schemas
- Synthetic evaluation fixtures and a field-level precision/recall CLI
- An optional local Apple Vision image-to-fields scanner isolated from the core

## Coordinate contract

Every bounding box uses a normalized unit square on the upright front of the card:

- Origin: bottom-left
- `x`: increases to the right
- `y`: increases upward
- `width` and `height`: fractions of the card dimensions
- Every component must be between `0` and `1`, and the rectangle must fit inside the unit square

This matches Apple Vision's normalized orientation. Adapters for top-left systems must convert `y` with `1 - top - height`.

## Quick start

```swift
import CardFieldCore

let observations = [
    OCRToken(
        text: "Alex Kim",
        boundingBox: .init(x: 0.10, y: 0.75, width: 0.35, height: 0.08),
        confidence: 0.97,
        language: "en"
    )
]

let result = try CardFieldClassifier().classify(observations)
print(result.fullName?.normalizedValue ?? "Unresolved")
```

The engine returns suggestions, never confirmed facts. A host should require review before saving or acting on a result.

Apple-platform hosts can run the complete local front-image pipeline through the adapter:

```swift
import AppleVisionAdapter
import Foundation

func scanCardFront(_ frontImageData: Data) throws {
    let scanner = AppleVisionScanner(
        configuration: .init(
            recognitionLanguages: ["ko-KR", "en-US"],
            automaticallyDetectsLanguage: true
        )
    )
    let scan = try scanner.scan(imageData: frontImageData)

    print(scan.fields.fullName?.normalizedValue ?? "Unresolved")
    print(scan.fields.emailAddresses.map(\.normalizedValue))
}
```

Encoded-image EXIF orientation is honored automatically. For a raw `CGImage`, pass the orientation needed to make the card upright. The synchronous scanner should run away from latency-sensitive UI work. It retains no image and performs no network request.

For a complete integration walkthrough, see the [CardFieldCore DocC catalog](Sources/CardFieldCore/CardFieldCore.docc/CardFieldCore.md).

## Package products

- `CardFieldCore`: contracts, normalization, rules, classification, confidence, evidence, corrections, and sanitization
- `AppleVisionAdapter`: locally recognizes a front image with Vision, converts observations into core tokens, and classifies them
- `CardFieldEvaluation`: decodes synthetic fixtures and reports field-level precision and recall
- `card-field-eval`: command-line fixture runner

Run the package and evaluation suite:

```sh
swift test
swift run card-field-eval Fixtures/Synthetic/phase1.json
```

## Rules and corrections

Rule evaluation order is fixed:

1. Built-in base rules
2. Locale and industry packs, sorted by priority and identifier
3. Personal corrections, sorted by identifier

Rule packs are additive JSON vocabularies. Personal corrections remain local by default and should encode the smallest reusable pattern, such as an email-domain mapping, rather than a complete contact record. See [rule packs](Docs/RULE_PACKS.md) and the [local correction example](Examples/Corrections/local-corrections.json).

## Other OCR providers

Google ML Kit, Tesseract, cloud OCR, and browser OCR can implement the same adapter contract by emitting text, a bottom-left normalized bounding box, confidence, and an optional language tag. The core never imports provider types. See [adapter guidance](Docs/OCR_ADAPTERS.md).

## Scope and privacy

Only front-side local OCR adapters, OCR normalization, and field classification belong here. Relationship notes, meeting memories, relationship graphs, recommendations, identity resolution, shared contact databases, server deduplication, private user data, production datasets, image storage, and back-side analysis are out of scope.

The package has no telemetry or networking. Do not submit real card images, OCR output, names, email addresses, phone numbers, or addresses. Read [PRIVACY.md](PRIVACY.md) before contributing.

A CRM such as Relationship Memory can reuse the public interpretation contracts, rules, and evaluation tools while retaining real scans, corrections, contact records, identity matching, review UX, and relationship intelligence as private host capabilities. See the [integration boundary](Docs/RELATIONSHIP_MEMORY_INTEGRATION.md).

## Project documentation

- [Architecture](ARCHITECTURE.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Support policy](SUPPORT.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Status

Pre-release. Phase 1 provides a transparent rule-based baseline, not a trained model and not production-grade OCR. Public APIs and schemas may change before `1.0.0`; changes will be recorded in the [changelog](CHANGELOG.md). Locale coverage and evaluation breadth should grow through sanitized structural fixtures and openly reviewable rules.

## License

Apache License 2.0. See [LICENSE](LICENSE).
