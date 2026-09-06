# Private Holdout Evaluation

The private holdout runner compares targeted re-recognition enabled and disabled on real photos without moving those photos or their expected values into this repository. It is a local evaluation tool, not telemetry, storage, or a production scanner.

## External corpus

Set `PRIVATE_CARD_CORPUS_ROOT` to a directory outside the repository. The runner reads exactly `manifest.json` from that directory and resolves every image reference beneath the same root. Absolute paths, `.` or `..` components, duplicate references, symlink escapes, unknown field keys, and unavailable files fail closed.

The external manifest uses schema version 1:

```json
{
  "schemaVersion": 1,
  "cases": [
    {
      "image": "card-001.jpg",
      "expected": {
        "fullName": ["Private Example"],
        "emailAddresses": ["private@example.com"],
        "mobilePhoneNumbers": ["+1 202-555-0100"]
      },
      "recognitionLanguages": ["en-US"],
      "automaticallyDetectsLanguage": true,
      "attemptsCardIsolation": true
    }
  ]
}
```

The example is fictional. A real manifest and its images must remain private and untracked. The schema intentionally has no confidence-limit setting: the runner always exercises the shipped `0.35` targeted re-recognition threshold.

## Running

```sh
PRIVATE_CARD_CORPUS_ROOT=/external/private-corpus \
  swift run card-field-private-benchmark --warmup 1 --runs 3 --bootstrap 2000 --pretty
```

Do not paste the resulting environment value into issues, logs, or reports. When the variable is missing, the command exits successfully with a fixed `privateCorpusUnavailable` skip result. Other failures print only a generic message so decoding and filesystem errors cannot disclose the root or image reference.

Each case runs at least three paired repetitions. Enabled-first and disabled-first order alternates by stable sorted input position and run. The report contains only corpus counts, exact and review rates, field-family support, false clears, natural execution count, isolation/fallback counts, request and duration distributions, recovered/regressed totals, and deterministic case-cluster bootstrap intervals. It excludes OCR text, alternatives, confidence, image data, filenames, paths, hashes, arbitrary tags, and case identifiers.

## Evidence gate

- Fewer than four cases naturally executing targeted re-recognition is `insufficientNaturalExecutions`.
- Any regressed field or an enabled p95 increase greater than both 100 ms and 50% of disabled p95 is `rejectPolicyChange`.
- Passing those guards is only `eligibleForHumanReview`; it does not approve a production policy change.

The runner never changes scanner defaults or the confidence threshold to manufacture execution. Public golden and synthetic regression suites remain the release gates regardless of private results.
