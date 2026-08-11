# ``CardFieldCore``

Interpret business-card OCR as structured, explainable field suggestions without storing or transmitting card data.

## Overview

`CardFieldCore` begins after an OCR provider has recognized the upright front of a card. It normalizes provider-neutral ``OCRToken`` values and uses deterministic rules to produce a ``CardFieldResult`` containing confidence, evidence, alternatives, source-token identifiers, warnings, and unresolved lines.

The module does not accept images, perform OCR, access the network, persist results, or resolve identities. Treat every classified value as an editable suggestion and require an appropriate host review policy before saving or acting on it.

Use an adapter such as the separate `AppleVisionAdapter` target to convert provider observations into the coordinate contract expected by the core. Keep capture, consent, storage, contact matching, and relationship intelligence in the host application.

## Topics

### Essentials

- <doc:PrivacyFirstInterpretation>
- ``CardFieldClassifier``
- ``OCRToken``
- ``NormalizedBoundingBox``
- ``CardFieldResult``

### Explainable results

- ``CardField``
- ``ClassifiedValue``
- ``AlternativeCandidate``
- ``Evidence``
- ``CardFieldWarning``

### Rules and local corrections

- ``RulePack``
- ``PhoneKind``
- ``CorrectionStore``
- ``PersonalCorrection``
- ``EmptyCorrectionStore``
- ``InMemoryCorrectionStore``
- ``LocalJSONCorrectionStore``

### Privacy-safe contributions

- ``ContributionSanitizer``
- ``ContributionDraft``
- ``SanitizedContributionToken``
- ``SanitizedCorrectionSummary``
