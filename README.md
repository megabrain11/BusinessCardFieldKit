# BusinessCardFieldKit

[![CI](https://github.com/megabrain11/BusinessCardFieldKit/actions/workflows/ci.yml/badge.svg)](https://github.com/megabrain11/BusinessCardFieldKit/actions/workflows/ci.yml)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](Package.swift)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2013%2B%20%7C%20iOS%2017%2B-lightgrey)](Package.swift)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

BusinessCardFieldKit is a privacy-first Swift package for turning business-card images or
provider-neutral OCR tokens into structured, reviewable field suggestions. It exists to provide
the explainable interpretation layer between OCR and an application's contact-review workflow.

On Apple platforms, the optional `AppleVisionAdapter` runs the image pipeline locally with Apple
Vision. The provider-neutral `CardFieldCore` has no image, Vision, storage, telemetry, or networking
dependency. It applies deterministic rules and returns confidence, evidence, alternatives, source
token identifiers, warnings, and unresolved lines instead of silently treating suggestions as
facts.

Key properties:

- **Local by design:** OCR and barcode recognition use on-device Apple frameworks; the package
  contains no networking or telemetry path.
- **Deterministic and explainable:** identical tokens, package version, and rule packs produce the
  same classified result, with evidence and source provenance attached.
- **Human-review first:** weak or conflicting evidence remains unresolved or carries an explicit
  review warning. The package never writes contacts or auto-merges identities.
- **Multilingual:** conservative script inference and name handling cover Korean, Latin, CJK, and
  mixed layouts without requiring a cloud service.
- **Composable:** callers can use the complete Apple Vision pipeline or provide `OCRToken` values
  from another OCR provider.

BusinessCardFieldKit is not a contact database, identity service, CRM, camera layer, or image
store. Hosts remain responsible for capture, consent, review, persistence, and deletion.

## Installation

Add the package in Xcode with **File > Add Package Dependencies**, using:

```text
https://github.com/megabrain11/BusinessCardFieldKit.git
```

Or add it to `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "YourApp",
  platforms: [
    .macOS(.v13),
    .iOS(.v17)
  ],
  dependencies: [
    .package(
      url: "https://github.com/megabrain11/BusinessCardFieldKit.git",
      from: "0.2.0"
    )
  ],
  targets: [
    .target(
      name: "YourApp",
      dependencies: [
        .product(name: "CardFieldCore", package: "BusinessCardFieldKit"),
        .product(name: "AppleVisionAdapter", package: "BusinessCardFieldKit")
      ]
    )
  ]
)
```

Depend on `CardFieldCore` alone when the host already has OCR observations. Add
`AppleVisionAdapter` for local image recognition on supported Apple platforms. The consuming target
must support macOS 13 or later or iOS 17 or later. Because the package is pre-`1.0`, pin an exact
version or commit when an integration requires a controlled upgrade window.

## Quick start

```swift
import CardFieldCore

let observations = [
  OCRToken(
    id: "name",
    text: "Avery Quinn",
    boundingBox: .init(x: 0.10, y: 0.75, width: 0.35, height: 0.08),
    confidence: 0.97,
    language: "en"
  ),
  OCRToken(
    id: "email",
    text: "avery.quinn@example.com",
    boundingBox: .init(x: 0.10, y: 0.25, width: 0.55, height: 0.05),
    confidence: 0.99,
    language: "en"
  )
]

let result = try CardFieldClassifier().classify(observations)
print(result.fullName?.normalizedValue ?? "Unresolved")
print(result.emailAddresses.map(\.normalizedValue))
print(result.warnings)
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
  print(scan.fields.warnings)
}
```

Encoded-image EXIF orientation is honored automatically. For a raw `CGImage`, pass the orientation needed to make the card upright. The synchronous scanner should run away from latency-sensitive UI work. It retains no image and performs no network request.

For local image testing on Apple platforms, use the included command:

```sh
swift run card-field-scan --language ko-KR --language en-US ./card-front.jpg
```

The command writes reviewable structured JSON to standard output and omits raw OCR tokens unless `--include-tokens` is requested. See [Local Image Scanning](Docs/IMAGE_SCANNING.md) for region-selection metadata, batch usage, CRM review guidance, and known limits.

For a complete integration walkthrough, see the [CardFieldCore DocC catalog](Sources/CardFieldCore/CardFieldCore.docc/CardFieldCore.md).

## Coordinate contract

Every bounding box uses a normalized unit square on the upright card:

- Origin: bottom-left
- `x`: increases to the right
- `y`: increases upward
- `width` and `height`: fractions of the card dimensions
- Every component must be between `0` and `1`, and the rectangle must fit inside the unit square

This matches Apple Vision's normalized orientation. Adapters for top-left systems must convert `y`
with `1 - top - height`.

## Package products

- `CardFieldCore`: contracts, normalization, rules, classification, confidence, evidence, corrections, sanitization, layout grouping, and script-based language inference
- `AppleVisionAdapter`: locally enhances and recognizes a card image with Vision, converts observations into core tokens with alternative readings, classifies them, and optionally decodes card-back barcodes; the projective masking strategy remains opt-in
- `CardFieldEvaluation`: decodes synthetic fixtures and reports field-level precision and recall
- `AppleVisionBenchmarking`: renders versioned synthetic front and back corpora and emits aggregate-only OCR, barcode, merge, and latency evidence, including the default-off conditional dual-pass, projective barcode-masking, and bounded barcode-recovery experiments
- `card-field-eval`: command-line fixture runner
- `card-field-scan`: local Apple-platform image scanner that emits structured JSON
- `card-field-benchmark`: local Apple-platform benchmark for p50/p95 latency, request counts, execution rates, and exact-field parity without OCR payloads
- `card-field-private-benchmark`: environment-gated real-photo holdout runner that emits aggregate-only paired evidence
- `card-field-private-back-benchmark`: environment-gated card-back runner that emits aggregate-only barcode, merge, review, and latency evidence

CI and local release validation use one entry point:

```sh
Scripts/check-repository.sh
```

It runs strict `swift format` linting, a package build, all tests without parallel execution, both
synthetic field-evaluation corpora, CLI smoke tests, aggregate synthetic OCR/card-back benchmarks,
DocC conversion with warnings as errors, JSON syntax checks, and the repository credential scan.
See [Contributing](CONTRIBUTING.md) for prerequisites and focused commands.

Use `card-field-benchmark --targeted-evidence` with the separately versioned targeted stress manifest to compare targeted re-recognition enabled and disabled without changing scanner defaults. Reports remain aggregate-only and contain no OCR payloads or case identifiers.

The regular benchmark interleaves shipped and conditional dual-pass scans per scene. The experiment remains disabled in `AppleVisionScanConfiguration` unless a host explicitly enables `AppleVisionConditionalDualPassOptions`; synthetic request savings are not a release recommendation.

Private real-photo evaluation uses a separate external root and the shipped confidence threshold. See [Private Holdout Evaluation](Docs/PRIVATE_HOLDOUT_EVALUATION.md). No private image, expected value, filename, path, or per-case output belongs in this repository.

Card-back regression uses fourteen deterministic runtime-rendered scenes through `card-field-benchmark --card-back-evidence`. Real-photo back evaluation uses a separate external root and at least three repetitions; see [Card-Back Evaluation](Docs/CARD_BACK_EVALUATION.md). Synthetic success is not a physical-device or production release approval.

To measure the exact projective barcode-mask experiment against the shipped rectified-image
redetection strategy, run `card-field-benchmark --card-back-mask-experiment --warmup 1 --runs 5
--pretty Fixtures/CardBack/manifest.json`. The report is aggregate-only and includes field/token/
barcode/card-region parity, signed latency deltas, isolated-sample request reduction, and
fail-closed fallback counts. The experiment is disabled in normal scans and its synthetic timing
does not justify changing the default.

With an external private card-back root, add `--projective-mask-experiment` to
`card-field-private-back-benchmark` to collect the same paired parity, request, fallback, and signed
latency evidence over real photos. The runner alternates strategy order deterministically, requires
at least three measured repetitions, and emits aggregate data only. An unavailable private root is
reported as a redacted skip, never as passing evidence.

To measure default-off source barcode recovery, run `swift run card-field-benchmark
--barcode-detection-recovery-experiment --pretty Fixtures/BarcodeDetectionStress/manifest.json`.
The paired report separates QR payload detection from field exactness, alternates execution order,
and reports only aggregate recovery/regression, request, parity, style, and latency evidence. The
experiment performs at most one enhanced full-frame request after an empty initial result and is
not approved as a default by synthetic evidence.

For aggregate physical-photo evidence, set an external `PRIVATE_CARD_BACK_CORPUS_ROOT` and add
`--barcode-detection-recovery-experiment`. The paired runner requires at least three measured runs,
alternates baseline/experimental order, and reports only truth-aware detection/exactness rates,
preservation, request counts, and signed latency distributions. Cases without decoded-payload
truth must declare `barcodeTruthAvailable: false`; they contribute only to detection rates. The
fixed gate requires four distinct recovered baseline failures, baseline-success preservation, no
field regression, and a p95 duration delta no greater than 250 ms. Even an eligible result permits
human review only and never enables recovery by default.

## Rules and corrections

Rule evaluation order is fixed:

1. Built-in base rules
2. Locale and industry packs, sorted by priority and identifier
3. Personal corrections, sorted by identifier

Rule packs are additive JSON vocabularies. Personal corrections remain local by default and should encode the smallest reusable pattern, such as an email-domain mapping, rather than a complete contact record. See [rule packs](Docs/RULE_PACKS.md) and the [local correction example](Examples/Corrections/local-corrections.json).

## Other OCR providers

Google ML Kit, Tesseract, cloud OCR, and browser OCR can implement the same adapter contract by emitting text, a bottom-left normalized bounding box, confidence, and an optional language tag. The core never imports provider types. See [adapter guidance](Docs/OCR_ADAPTERS.md).

## Reuse beyond business cards

AnswerSheetFieldKit reuses BusinessCardFieldKit's provider-neutral `OCRToken` and token-scanning
layer while keeping answer-sheet interpretation in its own project. This is a concrete example of
the package boundary being reusable infrastructure, not a claim of broad adoption.

## Scope and privacy

Only local OCR/barcode adapters, provider-neutral parsing, same-card front/back suggestion combination, OCR normalization, and field classification belong here. Relationship notes, meeting memories, relationship graphs, recommendations, cross-contact identity resolution, shared contact databases, server deduplication, private user data, production datasets, image storage, camera capture, and contact writes are out of scope.

The package has no telemetry or networking. Real business-card photos and their OCR or PII may be used only for private, transient local validation; they are never committed to this public repository. Do not submit real card images, OCR output, names, email addresses, phone numbers, or addresses. Read [PRIVACY.md](PRIVACY.md) before contributing.

A CRM such as Relationship Memory can reuse the public interpretation contracts, rules, and evaluation tools while retaining real scans, corrections, contact records, identity matching, review UX, and relationship intelligence as private host capabilities. See the [integration boundary](Docs/RELATIONSHIP_MEMORY_INTEGRATION.md).

## Project documentation

- [Architecture](ARCHITECTURE.md)
- [Local image scanning](Docs/IMAGE_SCANNING.md)
- [Card-back scanning](Docs/CARD_BACK_SCANNING.md)
- [Private holdout evaluation](Docs/PRIVATE_HOLDOUT_EVALUATION.md)
- [AI collaboration handoff](Docs/AI_COLLABORATION.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [v0.2.0 release notes](Docs/RELEASE_NOTES_0.2.0.md)
- [Support policy](SUPPORT.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Status

Pre-release. Phase 1 provides a transparent rule-based baseline, not a trained model and not production-grade OCR. Public APIs and schemas may change before `1.0.0`; changes will be recorded in the [changelog](CHANGELOG.md). Locale coverage and evaluation breadth should grow through sanitized structural fixtures and openly reviewable rules.

## License

Apache License 2.0. See [LICENSE](LICENSE).
