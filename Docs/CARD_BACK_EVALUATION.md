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

## Exact projective masking experiment

The shipped strategy remains `rectifiedRedetection`: after a card is isolated, Vision makes one
content-free barcode-region request on the exact rectified image used for OCR. The opt-in
`projectiveSourceObservation` strategy avoids that second request by mapping source barcode
quadrilaterals through a validated four-point homography. Non-finite, degenerate, singular, or
out-of-range mappings fail closed to the shipped redetection path. No source bounding-box
approximation is used, and public barcode geometry is unchanged.

Run the paired aggregate experiment with one warmup and five measured repetitions:

```sh
swift run card-field-benchmark \
  --card-back-mask-experiment --warmup 1 --runs 5 --pretty \
  Fixtures/CardBack/manifest.json
```

The separate schema-1 report contains only case/run counts, strategy identifiers, field/token/
barcode/card-region parity, unsigned request-reduction distributions, signed total and isolated
latency deltas, projective-applied samples, and fail-closed fallback counts. On the reference host,
all 70 paired samples were parity-identical; projective mapping applied on 10/10 isolated samples,
removed one barcode request on each isolated sample (p50/p95 reduction 1/1), and had an isolated
signed duration delta of −17.49 ms p50 and −1.86 ms p95. Total-scan timing was −0.23 ms p50 and
7.54 ms p95. These figures are synthetic and host-specific; they are evidence for further private
holdout measurement, not a release recommendation or default change.

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
p50/p95 latency, fixed request distributions, and evidence limitations. It deliberately omits
corpus version, tags, source identity, and per-case failures. If the environment variable is absent, the command exits
successfully with a redacted `privateCorpusUnavailable` skip; this is insufficient evidence, not a
passing private evaluation.

To compare exact projective mapping against the shipped rectified redetection path on the same
external images, run the opt-in paired experiment:

```sh
PRIVATE_CARD_BACK_CORPUS_ROOT=/external/private-card-backs \
  swift run card-field-private-back-benchmark \
    --projective-mask-experiment --warmup 1 --runs 3 --pretty
```

Baseline and experimental scans alternate first/second order deterministically by repetition and
sorted input position. The schema-1 comparison contains only field/token/barcode/card-region parity,
projective application and fallback counts, total and isolated request-reduction distributions,
signed latency deltas, run/case counts, and fixed limitations. It does not contain filenames,
paths, payloads, OCR, tokens, expected values, case identifiers, tags, or corpus identity. This
private aggregate can challenge the synthetic result but cannot itself promote the experimental
strategy or replace human physical-device acceptance.

## Interpretation and release boundary

All synthetic exactness checks must stay at 100% and the public-alpha field evaluator must retain
zero false positives and zero false negatives. A private aggregate can reveal regressions, but even
a perfect aggregate does not approve production rollout. Physical-device camera capture, varied
print materials and lighting, representative private photos, human review of mismatches, and CRM
acceptance remain separate release gates.

The scanner masks OCR tokens only against barcode observations from the exact upright image used for
recognition. Full-image scans reuse source barcode regions. Perspective-isolated scans use the
content-free rectified-image request by default, or the opt-in exact projective mapping experiment;
public barcode metadata stays in its existing source-image contract. Both paths prevent QR modules
from becoming names or organizations without a bounding-box approximation and preserve nearby email
and phone text. Direct regression tests cover projective isolation, multiple QR codes, unsupported
payloads, and EXIF rotation.
