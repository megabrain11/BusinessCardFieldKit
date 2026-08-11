# Changelog

All notable changes to BusinessCardFieldKit will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/). Before `1.0.0`, a minor release may contain breaking API or schema changes; those changes will be called out here with migration guidance.

## [Unreleased]

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

No release tags have been published yet.
