# Evaluation

Synthetic fixtures contain OCR observations and expected normalized field values. They contain no images and no real contact information.

## Corpora

- `Fixtures/Synthetic/phase1.json` is a three-case smoke corpus.
- `Fixtures/Synthetic/public-alpha.json` is a 26-case regression corpus for the public alpha.

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

Regression tests additionally cover rule layers, private corrections, deterministic output, and contribution sanitization.

Production evaluation data is outside this repository. Do not submit real OCR values or images. Contribute a sanitized structural layout and a separately authored fictional regression case.
