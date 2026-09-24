# Adaptive OCR Diagnostics

This document records the safe integration boundary for measuring a future conditional OCR strategy. It does not enable adaptive recognition and does not change the shipped OCR path.

## Contract

Diagnostics are opt-in through `AppleVisionScanConfiguration.diagnostics`. Disabled configuration creates no accumulator, reads no clock, and returns `nil` in `AppleVisionScanResult.diagnostics` and `AppleVisionTokenScanResult.diagnostics`.

An enabled, completed scan returns schema version 2 with:

- ordered aggregate durations for image decoding, preprocessing, card detection, saliency fallback, primary recognition, secondary recognition, dual-pass merge, targeted re-recognition, classification, and total;
- total Vision requests plus rectangle, saliency, all text, primary-text, secondary-text, and targeted-text request counts;
- configured/executed flags for dual-pass and targeted re-recognition; and
- configured/attempted/succeeded/fallback flags for card isolation; and
- a conditional dual-pass configured flag, total skip count, and fixed decision-reason counts.

Schema-1 payloads remain decodable and default all conditional fields to disabled or empty.

`targetedReRecognitionRequestCount` is a subset of `textRecognitionRequestCount`, not an additional request family. Total Vision requests equal rectangle + saliency + text requests. Candidate OCR requests accumulate under their matching stage and request kind. Targeted re-recognition runs at most once per scan, on the selected card or the full-image fallback. Targeted re-recognition is a containing duration, so it can overlap primary/secondary recognition durations. The total duration is measured independently and is not the sum of stages.

The payload is Codable and contains only fixed identifiers, numeric aggregates, and booleans. It cannot contain OCR text, candidate readings, token values or confidence, bounding boxes, source paths, image data, or arbitrary host metadata. The scanner does not log or persist the report.

## Determinism and parity

Production durations vary with the machine and Vision runtime. Report schema, stage ordering, request arithmetic, and execution flags are deterministic for a fixed path. Tests inject a controlled clock for exact values. Golden-scene tests compare diagnostics OFF and ON across all 50 generated cases and require identical tokens, fields, and card-region selection. A token-only regression additionally verifies dual-pass request counts and confirms no classification stage is emitted.

Diagnostics observe the current configuration; they do not themselves gate dual-pass, select candidates, refine tokens, or invoke the strict-field corrector. The independently opt-in conditional policy records its fixed outcome through diagnostics but owns the decision. Any future strategy must prove parity or a documented accuracy improvement against the golden and private evaluation suites.

## Adaptive branch audit

The historical `codex/adaptive-ocr-diagnostics` branch was audited without changing its branch or worktree. None of its commits were cherry-picked because the branch predates the reusable `scanTokens` path, column-aware classifier, and strict-field corrector.

| Commit | Decision | Reason |
|---|---|---|
| `650ace6` | Reimplemented | Retained disabled-by-default diagnostics, injected clock, timing, counters, and redaction intent; replaced its scan-only result and free-form contract with the current shared-pipeline, Codable fixed contract. |
| `0418fe4` | Partially reimplemented | Retained stage/request instrumentation concepts. Adaptive recognition, alternative promotion, and unrelated cancellation changes were not integrated. |
| `6e8a8c1` | Superseded | Documentation was rewritten for the current architecture and contract. |
| `c347bb7` | Deferred | Adaptive refinement scoping is policy, not diagnostics; it requires current-corpus measurements first. |
| `6c362e4` | Deferred | Digit/CJK weak-token expansion changes recognition behavior and remains outside this parity-only integration. |
| `c64f0e5` | Deferred | Structural dual-pass safety logic is part of the future conditional strategy. |
| `7226fd1` | Deferred | Condition-aware gating thresholds need evidence from the current evaluator. |
| `2319a42` | Deferred | Always dual-passing isolated crops is a strategy decision now measurable through request counts. |
| `72c78d2` | Deferred | A contact-evidence floor is an uncalibrated policy input. |
| `4c414b6` | Deferred | Whole-frame fallback safety behavior is a strategy decision, not an observation concern. |

The current strict-field corrector remains the sole owner of grammar-validated alternative selection. Diagnostics never rewrite alternatives or fields.

## What can be measured next

For each stable corpus configuration, collect aggregate reports over repeated runs and compare:

- total p50/p95 latency;
- primary, secondary, targeted, rectangle, and saliency request counts;
- the percentage of scans that actually execute dual-pass or targeted re-recognition;
- latency by isolated-card versus full-image fallback path; and
- unchanged field accuracy and review rates from the existing evaluators.

The public report intentionally cannot explain which token triggered a stage. Token-level attribution, OCR text logging, or source-image identifiers must not be added. If more diagnosis is needed, use a private transient evaluator that joins aggregate reports to its own ephemeral case identifiers outside this package and emits aggregate results only.

## Synthetic baseline

`AppleVisionBenchmarking` expands 25 versioned layouts into two deterministic variants each and renders the 50 images with Core Text/Core Graphics at runtime. `card-field-benchmark` performs separate warmup and measured passes for four configurations while leaving the shipped default unchanged.

One warmup plus one measured run on the development machine produced this directional baseline:

| Configuration | Exact cases | Total p50 | Total p95 | Text requests p50/p95 |
|---|---:|---:|---:|---:|
| Shipped default | 50/50 | 143 ms | 195 ms | 2/2 |
| Dual-pass disabled | 46/50 | 104 ms | 184 ms | 1/1 |
| Targeted re-recognition disabled | 50/50 | 162 ms | 226 ms | 2/2 |
| Both disabled | 46/50 | 96 ms | 143 ms | 1/1 |

The sample is sufficient to reject unconditional single-pass as a default: it saved a request and reduced median latency but lost exact fields in 8% of cases. Targeted re-recognition did not execute in this corpus, so its isolated latency effect remains unmeasured rather than proven unnecessary. Timing values vary by hardware and load; rerun the benchmark instead of treating this table as a stable product SLA.

At most two future experimental gates are justified:

1. A default-OFF dual-pass skip may be evaluated only when the primary pass has complete, unambiguous strict-contact syntax and no low-confidence or multilingual evidence. It must retain 50/50 synthetic parity and pass a private real-photo holdout before any broader rollout.
2. Targeted re-recognition may remain conditional on an actual low-confidence candidate, as it already is. A new disable policy is not justified until a corpus exercises the stage and measures both recoveries and cost.

## Targeted re-recognition stress evidence

The separate `targeted-rerecognition-stress-1.0.0` corpus contains 12 layouts with two deterministic variants each. It covers small email/URL/phone lines, local blur, low contrast, contact-only glare/shadow, mixed Korean and English, card-isolation success, and forced full-image fallback. Four cases retain the shipped `0.35` threshold, eighteen use a documented `1.0` calibration threshold to exercise the stage, and two use a zero-threshold non-execution control. Calibration changes benchmark configuration only; it is not a proposed production setting.

One warmup plus one measured paired run produced:

| Configuration | Exact cases | Targeted execution | Total p50/p95 | Targeted p50/p95 | Targeted requests p50/p95 |
|---|---:|---:|---:|---:|---:|
| Enabled | 23/24 | 75% | 341/420 ms | 211/261 ms | 2/2 |
| Disabled | 23/24 | 0% | 133/176 ms | N/A | 0/0 |

Paired outcomes were zero recovered fields, zero regressed fields, zero new review recommendations, and zero resolved review recommendations. Both configurations shared one email false clear and the corresponding website mismatch, so the targeted stage neither caused nor repaired it. All four shipped-threshold stress cases remained below the execution gate; the eighteen calibrated cases executed, and the two controls did not.

Verdict: **insufficient evidence for a policy change**. Forced execution adds substantial synthetic latency without a demonstrated recovery, while the shipped threshold remains dormant even in these generated stress scenes. Keep the current fail-safe implementation and default configuration unchanged. The next useful evidence must come from private real photos that naturally produce confidence at or below `0.35`, with aggregate-only reporting of recoveries and regressions.

### Contact-syntax follow-up

The one shared failure was reproduced independently of targeted re-recognition: strong blur inserted whitespace around an email `@`, after which the domain fragment also matched website syntax. Base email extraction now compacts whitespace only around a complete syntactically valid email and preserves the spaced OCR text as `originalValue`; website extraction recognizes the preceding spaced `@` and suppresses the embedded domain. Prose without a dotted domain remains unresolved, and an independent website on the same OCR line still survives.

A repeat of one warmup plus one measured run now produces 24/24 exact cases, zero false clears, zero recoveries, and zero regressions on both targeted configurations. Enabled p50/p95 was 369/475 ms with 75% execution; disabled p50/p95 was 144/217 ms with no targeted execution. The accuracy repair is therefore a classifier normalization improvement, not evidence that forced targeted re-recognition is useful. The policy verdict remains unchanged.

## Private holdout runner

`card-field-private-benchmark` now provides the bounded evaluator for that next evidence. It reads a schema-v1 manifest and images only from `PRIVATE_CARD_CORPUS_ROOT`, rejects path traversal and symlink escape, preserves the shipped `0.35` threshold, alternates paired execution order, requires at least three measured repetitions, and calculates deterministic case-cluster bootstrap intervals. Its output has no corpus label, filename, path, hash, case identifier, OCR value, token, confidence, or image field.

At least four distinct cases must naturally execute targeted re-recognition before the report can leave `insufficientNaturalExecutions`. Any regression or excessive p95 increase rejects a policy change; otherwise the strongest possible result is `eligibleForHumanReview`, not automatic approval. The current development environment has no private corpus configured, so no real-photo result or production claim exists yet.

## Conditional dual-pass experiment

The default-off `AppleVisionConditionalDualPassOptions` gate was implemented after the observation-only baseline. It requires at least two complete strict-contact families plus high confidence, Latin-only single-script text, a simple single-column layout, bounded content, no competing valid alternatives or country-code form, and no base-classifier review warning. Full-image fallback and targeted recognition are structural rejection paths. Any rejection executes the existing opposite-correction request and deterministic merge unchanged.

Diagnostics schema 2 records only whether the experiment was configured, the number of skipped requests, and counts keyed by a fixed reason enum. Benchmark schema 2 interleaves shipped and experimental scans per scene and exposes paired aggregate exact/review changes, second-request totals, and p50/p95 deltas. Legacy diagnostics schema 1 decodes with empty conditional fields.

One warmup plus three interleaved measured runs produced:

| Corpus | Samples | Exact baseline / experiment | Review changes | Skipped secondary requests | Total p50 delta | Total p95 delta |
|---|---:|---:|---:|---:|---:|---:|
| Golden 25 × 2 | 150 | 150 / 150 | 0 | 72 | -20.6 ms | -4.1 ms |
| Targeted stress 12 × 2 | 72 | 72 / 72 | 0 | 39 | -61.9 ms | -69.2 ms |

Golden eligibility was 48%; rejection totals across three runs were cropped content 24, low confidence 36, multilingual evidence 6, and ambiguous alternatives 12. Stress decisions additionally retained dual-pass for all 54 targeted requests and six full-image fallbacks. A targeted request can execute a secondary pass after the standard request was skipped, so per-scan `dualPassExecuted` and `dualPassSkipRate` are intentionally not complements.

Verdict: retain the implementation only as an opt-in experiment. Synthetic evidence shows no field or review regression and real request savings, but does not establish real-photo, device, language, or OS-general performance. Default enablement and release promotion are rejected until the external private holdout passes with the same fail-closed decision boundary.
