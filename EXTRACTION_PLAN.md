# Extraction Plan

## Reusable concepts

- A normalized OCR observation containing text, confidence, language, and unit-square layout coordinates.
- Deterministic normalization and rule-based field classification.
- Conservative person-name promotion with explicit uncertainty.
- Multilingual role and organization vocabularies.
- Label-aware phone parsing, bare-domain recognition, address cues, and slogan exclusion.
- Per-field confidence and source evidence.

## App-specific code that stays in Relationship Memory

- UIKit, SwiftUI, PhotosUI, camera capture, and image orientation handling.
- Business-card image resizing, protected file storage, deletion lifecycle, and back-image retention.
- Relationship Memory draft models, UI localization keys, review screens, and person-record mapping.
- CRM identity, relationship, synchronization, and deduplication behavior.

## Phase 1 extraction sequence

1. Define a language-neutral JSON input/output contract using bottom-left unit-square coordinates.
2. Implement normalization, base rules, optional locale or industry packs, and a private correction overlay in `CardFieldCore`.
3. Keep Apple Vision conversion in the separate `AppleVisionAdapter` target.
4. Add synthetic fixtures and field-level evaluation in `CardFieldEvaluation`.
5. Generate sanitized contribution drafts locally and require an explicit host-app action for sharing.
6. Integrate later by mapping Vision observations to core tokens and reviewed core results to Relationship Memory drafts.

No source code or personal data is copied from Relationship Memory. The existing implementation is used only as a behavioral reference.
