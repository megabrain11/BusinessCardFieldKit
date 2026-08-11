# Roadmap

BusinessCardFieldKit aims to become the small, dependable interpretation layer between OCR providers and review-first contact workflows. It should make field semantics portable without becoming an OCR service, contact database, or CRM.

The roadmap is capability-based rather than date-based. Priorities may change as synthetic evaluation and privacy-safe community reports reveal higher-value work.

## Product boundary

| Public BusinessCardFieldKit | Host-owned CRM capability |
| --- | --- |
| OCR token and result contracts | Real card images and raw production OCR |
| Deterministic classification and evidence | Contact records and user corrections |
| General locale and industry rule packs | Identity matching, merging, and deduplication |
| Synthetic fixtures and conformance tools | Review UI, retention, consent, and synchronization |
| Provider adapters and contribution sanitization | Relationship notes, graphs, recommendations, and private evaluation data |

This boundary lets Relationship Memory reuse and improve a stable field-interpretation foundation while keeping its product data, user experience, and relationship intelligence private.

## Toward `0.1.0`: trustworthy baseline

- Harden ambiguous-field behavior so weak evidence remains unresolved.
- Add meaningful Apple Vision coordinate, confidence, and observation-conversion tests.
- Expand the synthetic corpus across layout variations, failure cases, Korean, English, and mixed-language cards.
- Document the public API and contract-version policy.
- Establish repeatable release, CI, security-reporting, and privacy-review checks.

Exit signal: the package builds cleanly, every supported field has positive and false-promotion coverage, schemas and examples validate, and known limitations are documented.

## Toward `0.2.0`: measured CRM adoption

- Publish a shadow-mode integration pattern that compares an existing parser with `CardFieldCore` without changing saved contacts.
- Define local, privacy-preserving quality measures: per-field correction rate, unresolved rate, false promotion rate, and review completion rate.
- Add adapter conformance fixtures so OCR providers can demonstrate coordinate and identifier compatibility.
- Make result and rule-pack migrations explicit and testable.

For Relationship Memory, adoption should progress from shadow output, to reviewer-visible suggestions, to selected default fields only after field-specific thresholds are met. The host should pin a package version and retain a rollback path.

## Toward `0.3.0`: safe rule-pack ecosystem

- Add rule-pack linting and compatibility checks.
- Grow locale and industry coverage through fictional fixtures and sanitized structural reports.
- Document quality requirements and maintenance ownership for community packs.
- Add provider adapters only when they can remain thin, deterministic, and independently tested.

## Toward `1.0.0`: stable interpretation contract

- Stabilize Swift and JSON input/output contracts under semantic versioning.
- Publish a compatibility and deprecation policy with migration windows.
- Maintain representative conformance suites for supported fields, rule packs, and adapters.
- Complete an external privacy and security review of the package boundary.

## How work is prioritized

Changes rank higher when they improve false-promotion safety, explainability, provider neutrality, synthetic test coverage, or measurable host integration. Features that require real personal data, networking, centralized correction collection, automatic identity merges, or private CRM behavior do not belong in this repository.
