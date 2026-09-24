# Evaluation

Synthetic fixtures contain OCR observations and expected normalized field values. They contain no images and no real contact information.

## Corpora

- `Fixtures/Synthetic/phase1.json` is a three-case smoke corpus.
- `Fixtures/Synthetic/public-alpha.json` is a 26-case regression corpus for the public alpha.
- `Fixtures/GoldenScenes/manifest.json` is a 25-layout, 50-case synthetic image corpus. Each layout expands into exactly two deterministic capture variants at runtime; no image binary is committed.
- `Fixtures/TargetedReRecognition/manifest.json` is a separate 12-layout, 24-case stress corpus for measuring targeted re-recognition execution and cost without weakening golden expectations.

The public-alpha corpus covers:

- Korean, English, mixed Korean and English, mixed Latin and CJK, alternate, and long multipart names
- Vertical, same-line name and role, organization-only, QR-heavy, and two-column layouts
- Uppercase and numeric organizations, plus government, university, association, foundation, and research institutions
- Compact English and Korean phone labels, multiple email addresses, bare domains, professional profiles, and social handles
- Departments and addresses from multiple countries
- Slogans, taglines, and low-confidence text that must remain unresolved

Every identity and organization is manually invented for this repository. Contact domains use `.example`. Fixed professional-profile hosts use fictional `public-alpha-` slugs. Phone values use fictional North American `202-555-01xx` examples or conspicuous zero-sequence Korean test values.

## Running the evaluator

Run either corpus:

```sh
swift run card-field-eval Fixtures/Synthetic/phase1.json
swift run card-field-eval Fixtures/Synthetic/public-alpha.json
```

The JSON report provides true positives, false positives, false negatives, precision, and recall for every field. A field with no expected or predicted values receives precision and recall of `1` because no error occurred.

The test suite decodes the public-alpha fixture through the public evaluation contract, rejects duplicate identifiers and unknown expected-field keys, checks synthetic contact namespaces, and requires zero false positives and zero false negatives under the base classifier.

The golden manifest covers English, Korean, and mixed-script content across horizontal, portrait, compact, two-column, isolated, perspective, low-contrast, glare, shadow, blur, QR, crop, overlapping-card, and complex-background conditions. Every case runs through the unchanged default pipeline, the opt-in column-aware classifier, and the opt-in strict-field corrector. Diagnostics OFF and ON must preserve identical tokens, fields, and card-region selection across all 50 cases.

Run the aggregate-only diagnostics benchmark:

```sh
swift run card-field-benchmark --warmup 1 --runs 3 --pretty Fixtures/GoldenScenes/manifest.json
```

The benchmark compares the shipped default, dual-pass disabled, targeted re-recognition disabled, and both disabled. It separates warmup runs from measured runs and reports p50/p95 total and stage latency, Vision request distributions, execution/fallback rates, exact-field rate, review rate, and tag groups with at least four samples. Small tag groups are counted but omitted. Reports contain no OCR text, token values or confidence, image data, paths, or case identifiers.

Synthetic timing is a local engineering baseline, not a device or production performance claim. Physical-device and private real-photo evaluation remain required before changing the shipped default.

Run the targeted-stage comparison independently:

```sh
swift run card-field-benchmark --targeted-evidence --warmup 1 --runs 3 --pretty Fixtures/TargetedReRecognition/manifest.json
```

The stress manifest contains four shipped-threshold cases, eighteen calibrated-threshold cases that ensure the stage can be measured, and two non-execution controls. Calibrated cases are instrumentation evidence only; they do not recommend changing the production confidence limit. The paired report counts recovered and regressed fields, new and resolved review recommendations, false clears, per-field exact rates, targeted requests, and total/targeted p50/p95 durations. It has no per-case output or tag group small enough to identify one scene.

For transient real-photo evidence, use the separately documented [private holdout runner](PRIVATE_HOLDOUT_EVALUATION.md). Its manifest and images remain outside the repository, it always uses the shipped `0.35` threshold, and it emits no source identity or OCR content. Missing private configuration is an explicit safe skip rather than a public CI failure.

The public-alpha corpus runs under the default classifier, the opt-in column-aware phone linker, and the opt-in strict-field corrector. Every configuration must retain zero false positives and zero false negatives before an experimental path can broaden its scope.

Regression tests additionally cover rule layers, private corrections, deterministic output, and contribution sanitization.

Production evaluation data is outside this repository. Do not submit real OCR values or images. Contribute a sanitized structural layout and a separately authored fictional regression case.
