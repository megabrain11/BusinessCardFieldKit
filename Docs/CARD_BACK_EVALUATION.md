# Card-Back Evaluation

BusinessCardFieldKit has two local card-back evaluation paths. Both exercise barcode detection,
payload-kind classification, structured vCard or URL fields, front/back merge behavior, duplicate
suppression, review decisions, and total scan latency. Neither path stores or prints decoded
payloads, OCR text, image data, paths, or case identifiers.

## Synthetic regression corpus

`Fixtures/CardBack/manifest.json` contains fourteen fictional scene descriptions and sixteen QR
codes. Images are generated deterministically at runtime rather than committed. Coverage includes
vCard 3.0 and 4.0, explicit URLs, unsupported payloads, small and low-contrast codes, rotation,
perspective distortion, multiple codes, QR plus visible contact text, front/back duplicates, and
identity conflicts that require review. Two scenes apply one projective transform to an entire card,
including its text and QR codes, and require automatic card isolation to succeed.

```sh
swift run card-field-benchmark \
  --card-back-evidence --warmup 1 --runs 3 --pretty \
  Fixtures/CardBack/manifest.json
```

The schema-3 report is aggregate-only. It includes fixed stage-duration and barcode-request
distributions collected through default-off back-scan diagnostics. The diagnostics summary is
optional so schema-2 reports remain decodable. `syntheticOnly` means the corpus is suitable for
deterministic regression testing but cannot establish camera, lighting, print, device, or real-photo
performance.

One local warmup plus three measured runs produced 42 samples. All field and decision rates stayed
at 100%. The six isolated samples executed exactly one additional masking request; its direct stage
span measured p50 14.4 ms and p95 21.1 ms on that host. This is a synthetic, machine-specific stage
measurement, not a causal production latency guarantee or justification for changing the default.

## External private corpus

Real card photos and expected contact values must remain outside this repository. Create an
external directory containing `manifest.json` and image files, then set
`PRIVATE_CARD_BACK_CORPUS_ROOT` for one transient run. Image references must be relative regular
files under that root; absolute paths, traversal, duplicate references, symlink escape, unavailable
files, and unknown expected fields fail closed.

```json
{
  "schemaVersion": 1,
  "cases": [
    {
      "image": "back-001.jpg",
      "expectedPayloadKinds": ["vCard"],
      "backExpected": {
        "fullName": ["Fictional Person"],
        "emailAddresses": ["person@private.example"]
      },
      "front": {},
      "mergedExpected": {
        "fullName": ["Fictional Person"],
        "emailAddresses": ["person@private.example"]
      },
      "reviewExpected": false,
      "recognitionLanguages": ["ko-KR", "en-US"],
      "automaticallyDetectsLanguage": true,
      "attemptsCardIsolation": true
    }
  ]
}
```

```sh
PRIVATE_CARD_BACK_CORPUS_ROOT=/external/private-card-backs \
  swift run card-field-private-back-benchmark --warmup 1 --runs 3 --pretty
```

At least three measured repetitions are mandatory. The completed JSON contains only counts, rates,
p50/p95 latency, fixed request distributions, and evidence limitations. It deliberately omits corpus version, tags, source
identity, and per-case failures. If the environment variable is absent, the command exits
successfully with a redacted `privateCorpusUnavailable` skip; this is insufficient evidence, not a
passing private evaluation.

## Interpretation and release boundary

All synthetic exactness checks must stay at 100% and the public-alpha field evaluator must retain
zero false positives and zero false negatives. A private aggregate can reveal regressions, but even
a perfect aggregate does not approve production rollout. Physical-device camera capture, varied
print materials and lighting, representative private photos, human review of mismatches, and CRM
acceptance remain separate release gates.

The scanner masks OCR tokens only against barcode observations from the exact upright image used for
recognition. Full-image scans reuse source barcode regions. Perspective-isolated scans run a
content-free masking-region request on the rectified card image, while public barcode metadata stays
in its existing source-image contract. This prevents QR modules from becoming names or organizations
without a bounding-box approximation and preserves nearby email and phone text. Direct regression
tests cover projective isolation, multiple QR codes, unsupported payloads, and EXIF rotation.
