# AI Collaboration Handoff

Living document for humans and AI agents (Codex, Claude Code, others). Update the relevant section when you finish significant work. Newest entries at the top.

## Session 2026-08-30 — Source barcode detection stress recovery (completed)

Goal: respond to the observed source-QR detection bottleneck with a bounded, measurable experiment
without changing the shipped path or committing any private card data.

### What changed

1. **Default-off one-request recovery**: after an empty initial source barcode result only, the
   adapter performs deterministic full-frame upscale, grayscale, contrast, sharpening, and Otsu
   thresholding followed by exactly one retry. Initial success, preprocessing failure, and retry
   failure all preserve the baseline behavior.
2. **Content-free diagnostics v2**: back diagnostics add the source recovery request count and
   execution boolean with schema-1 decoding defaults. No payload, OCR text, token, confidence,
   geometry, image, path, or case identity is exposed.
3. **Independent stress corpus**: eighteen runtime-rendered fictional scenes cover tiny,
   very-low-contrast, blurred, center-overlaid, dot-styled, and strongly projective QR codes. The
   repository contains only the manifest; images are generated deterministically in memory.
4. **Paired aggregate benchmark**: `--barcode-detection-recovery-experiment` alternates execution
   order and separates QR payload exactness from field exactness. It reports only aggregate
   recoveries/regressions, field/token/card-region parity, bounded request counts, style summaries,
   and latency distributions.

### Evidence and decision

One warmup plus three measured runs produced 54 pairs. Baseline QR exactness was 66.7% and the
experiment reached 72.2%, recovering three repeated samples from one dot-style scene with zero QR
or field regressions. Baseline-exact preservation, token parity, and card-region parity were 100%.
The retry executed for 18/54 pairs; source request p95 increased from 1 to 2, while median extra
requests remained 0. Strong-perspective and most dot-style scenes remain unresolved.

Keep recovery default OFF. Synthetic recovery establishes that the bounded path can help, not that
it should ship enabled. The next decision requires an external aggregate-only physical-photo run
covering damaged, glossy, partial, stylized, and small QR codes across supported devices and Vision
versions.

## Session 2026-08-30 — Private projective card-back validation (completed)

Goal: carry the exact projective barcode-mask experiment into the external private card-back
boundary without changing the shipped scanner default or exposing private inputs.

### What changed

1. **Shared paired aggregation**: the synthetic and private runners now use the same deterministic
   schema-1 comparison builder for token, field, barcode, card-region, request, fallback, and signed
   duration evidence.
2. **Opt-in private experiment**: `card-field-private-back-benchmark
   --projective-mask-experiment` alternates baseline/experimental order by repeat and sorted input
   position. It requires three measured repetitions and leaves the existing private benchmark
   behavior unchanged when the flag is absent.
3. **Redacted envelope**: the command envelope gained an optional comparison payload with
   backward-compatible decoding. Reports omit filenames, root paths, OCR, tokens, payloads,
   expected values, tags, case identifiers, and corpus identity. A missing root remains an explicit
   redacted skip.
4. **Boundary regression tests**: tests cover real runner execution over a transient isolated-card
   scene, paired parity and request reduction, aggregate redaction, legacy envelope decoding, and
   the minimum-run guard.

### Decision and remaining risk

- Keep `.rectifiedRedetection` as the default. Private aggregate evidence is necessary but not
  sufficient for promotion; representative physical photos and human acceptance are still needed.
- Interpret signed latency deltas as host/runtime observations. Run multiple physical-device
  cohorts before treating them as production savings.
- Do not preserve private raw reports outside the configured corpus boundary or add per-case output.

## Session 2026-08-29 — Exact projective barcode-mask experiment (completed)

Goal: evaluate whether source barcode observations can replace the isolated-card masking request
without changing OCR fields, public barcode metadata, or the shipped default.

### What changed

1. **Fail-closed projective mapper**: `BarcodeMaskingExperiment.swift` maps each source barcode
   quadrilateral to the normalized rectified card image with a four-point homography solved by
   deterministic Gaussian elimination. Non-finite, degenerate, singular, or out-of-range geometry
   returns `nil`, which selects the existing exact rectified-image redetection path.
2. **Opt-in strategy contract**: `AppleVisionScanConfiguration.barcodeMaskingStrategy` defaults to
   `.rectifiedRedetection`. `.projectiveSourceObservation` is additive and experimental. Public
   barcode metadata remains source-based; only the internal OCR masking regions change.
3. **Content-free diagnostics**: back diagnostics add the strategy, projective-applied flag, and
   fallback count with backward-compatible decoding. No payload, OCR text, token value, geometry,
   image, path, or case identity is serialized.
4. **Paired aggregate benchmark**: `--card-back-mask-experiment` runs deterministic alternating
   baseline/experimental order and emits a separate schema-1 report with parity, unsigned request
   savings, signed total/isolated latency deltas, and fallback counts. The benchmark renders each
   scene once per pair and keeps all output aggregate-only.

### Verification and evidence

`swift format lint --strict --recursive Sources Tests`, `swift build`, and the focused projective
suite pass. The fourteen card-back scenes remain parity-identical for tokens, fields, detected
barcodes, and card-region selection. With one warmup and five measured runs (70 paired samples),
projective mapping applied to all 10 isolated samples with zero fallbacks; isolated request
reduction was 1 at p50/p95. Isolated signed duration delta was −17.49 ms p50 and −1.86 ms p95;
all-sample delta was −0.23 ms p50 and 7.54 ms p95 on the reference host.

### Decision and remaining risk

- Keep `.rectifiedRedetection` as the default. The experiment is useful for measuring request and
  latency savings but synthetic Core Text timing is machine-specific and cannot establish camera,
  glossy-print, damaged-code, or Vision-version behavior.
- Run the private card-back holdout and physical-device acceptance before considering promotion.
- Preserve the exact quadrilateral contract and fail-closed fallback; do not replace it with a
  bounding-box approximation or automatic rollout.

## Session 2026-08-29 — Card-back masking diagnostics (completed)

Goal: measure the extra barcode request used to mask QR regions after perspective isolation without
changing recognition policy, serializing private content, or adding default-path instrumentation.

### What changed

1. **Default-off back diagnostics v1**: `AppleVisionBackScanDiagnostics` reports fixed stage spans,
   source and isolated-mask barcode-request counts, and whether rectified mask detection executed.
   It contains no OCR text, decoded payload, confidence, geometry, image, path, token, or arbitrary
   metadata.
2. **Parity-preserving instrumentation**: disabled calls create no instrumentation object. Enabled
   calls keep nested token diagnostics off, measure source barcode detection, token recognition,
   rectified mask detection, classification/merge, and total scan time, and return identical tokens,
   fields, barcode metadata, and card-region decisions.
3. **Aggregate report v3**: card-back benchmark reports optionally include content-free stage and
   request distributions. The optional field keeps schema-2 reports decodable, and aggregation is
   independent of sample order.
4. **Path evidence**: disabled and full-image fallback scans issue one source barcode request. An
   isolated scan issues that request plus exactly one request on the rectified recognition image.

### Verification and evidence

`swift test --no-parallel` passes 180 tests. Diagnostics ON/OFF parity holds across all fourteen
synthetic back scenes. One warmup plus three measured runs produced 42 samples with all field and
decision rates at 100%. Six isolated samples executed the additional masking request; its direct
stage span was p50 14.4 ms and p95 21.1 ms on that host. Source requests were 1 at p50/p95, while
total barcode requests were 1 at p50 and 2 at p95.

### Decision and remaining risk

- Keep exact rectified-image redetection unchanged. Its measured synthetic cost is modest and
  preserves coordinate correctness; do not replace it with a bounding-box approximation.
- The outer total begins after encoded-image decoding, so it is a scanner-stage diagnostic rather
  than end-to-end ingestion latency.
- Machine-specific synthetic timing cannot establish real-camera value. Gloss, damaged or partial
  QR codes, device variance, and private CRM acceptance still require the external runner and human
  review before any default or optimization decision.

## Session 2026-08-29 — Exact isolated-card barcode masking (completed)

Goal: remove QR-shaped OCR noise after perspective card isolation without changing public barcode
geometry or approximating a source bounding box in rectified coordinates.

### What changed

1. **Exact recognition image handoff**: the token scanner now has a package-internal result that pairs the unchanged public token result with the exact upright image used for OCR. The image exists only for the synchronous call and is neither retained nor returned publicly.
2. **Coordinate-consistent masking**: disabled and fallback back scans reuse source barcode regions. Isolated scans run a content-free barcode-region request on the perspective-corrected recognition image, then filter only tokens that substantially overlap those rectified regions. Public decoded-barcode metadata remains source-based.
3. **Whole-card projective scenes**: the back corpus now contains fourteen cases and sixteen QR codes. Two cases transform the entire card, its nearby contact text, and one or two QR codes together and require `.isolated` rather than fallback.
4. **Aggregate contract v2**: reports add card-region decision accuracy. No OCR text, payload, geometry, path, image, token, or case identity is serialized.
5. **Regression coverage**: direct tests cover unsupported QR noise, nearby email and phone preservation, public/internal token parity, automatic perspective isolation, multiple QR codes, and EXIF rotation.

### Verification

`swift test --no-parallel` passes 176 tests. All fifty golden scenes remain exact in base,
column-aware, and strict-field configurations. The fourteen-case back corpus detects all sixteen QR
codes and holds payload-kind, back-field, merged-field, duplicate, review, and card-region decision
rates at 100%. Public-alpha remains zero false positives and zero false negatives.

### Remaining risk

- An isolated back performs one additional local barcode-region request. Its latency impact is included in total back-scan timing but not yet broken out as a public diagnostics stage.
- Real camera, glossy print, damaged QR, partial crop, device variance, and private CRM acceptance still require the external runner and human review.
- A completed private aggregate is evidence for review, never automatic approval.

## Session 2026-08-29 — Card-back aggregate evaluation (completed)

Goal: turn the new card-back scanner into a measurable regression surface and define a privacy-safe
real-photo acceptance boundary without committing any card image or decoded payload.

### What changed

1. **Deterministic back corpus**: `Fixtures/CardBack/manifest.json` defines twelve fictional runtime-rendered scenes and thirteen QR codes spanning vCard 3/4, URLs, unsupported content, small/low-contrast, rotation, perspective, multiple QR, visible text, duplicate suppression, and identity-conflict review.
2. **Aggregate contract**: `card-field-benchmark --card-back-evidence` reports only barcode counts, payload-kind/back/merged/duplicate/review rates, p50/p95 latency, and fixed tag coverage. It has no payload, OCR text, geometry, image, path, or case-identity field.
3. **QR OCR false-positive fix**: the back scanner classifies token-only OCR after removing tokens substantially overlapping detected barcodes in shared full-image coordinates. Perspective-isolated tokens fail closed and remain unchanged until exact coordinate mapping is available.
4. **External private boundary**: `card-field-private-back-benchmark` reads relative regular files only from `PRIVATE_CARD_BACK_CORPUS_ROOT`, rejects path escape, duplicate references and unknown fields, requires at least three measured runs, and emits no corpus identity or private tags. Missing configuration returns a redacted successful skip, which is insufficient evidence.
5. **Evidence result**: all twelve synthetic cases reproduce the thirteen expected barcode kinds, back fields, merged fields, duplicate decisions, and review decisions exactly. This remains synthetic-only evidence and cannot approve a physical-device or production rollout.

### Verification

`swift test --no-parallel` passes 173 tests. The card-back benchmark reports 12/12 exact cases,
13/13 detected barcode kinds, and 100% duplicate/review agreement. Public-alpha retains zero false
positives and zero false negatives. The official repository check includes the new CLI smoke test,
synthetic back run, and manifest JSON validation.

### Remaining risk

- QR-region masking is exact for disabled or full-image-fallback OCR. Perspective-isolated OCR uses rectified coordinates while barcode observations use source coordinates, so those tokens are conservatively retained.
- Real camera, glossy print, damaged QR, partial crop, device variance, and private CRM acceptance still require the external runner and human review.
- A completed private aggregate is evidence for review, never automatic approval.

## Session 2026-08-29 — Card-back barcode and vCard composition (completed)

Goal: implement the first still-missing, in-scope item from the module backlog without recreating mature core models, moving image types into the core, or adding host-owned camera/contact storage behavior.

### What changed

1. **Provider-neutral vCard parser**: `VCardParser` accepts vCard 3.0/4.0 strings and UTF-8/EUC-KR data, unfolds lines, decodes escaped and quoted-printable values, and maps only supported contact properties into sourced suggestions.
2. **Same-card composition**: `CardScanSession` returns front, optional back, and deterministic merged results. Duplicate contacts collapse, barcode evidence wins duplicates, phone subtypes deduplicate across families, and conflicting singular values preserve the losing candidate and require review.
3. **Local back adapter**: `CardBackScanner` combines the existing OCR pipeline with `VNDetectBarcodesRequest`. QR-only backs succeed without OCR text. vCard and explicit HTTP(S) URLs become fields; unsupported content exposes metadata without the raw payload.
4. **Boundary preserved**: `CardFieldCore` still imports Foundation only. Vision and image decoding remain in `AppleVisionAdapter`; no camera, Contacts framework, logging, storage, telemetry, or network behavior was added.
5. **Coverage**: fictional tests cover vCard versions, folded and escaped values, UTF-8/EUC-KR and quoted-printable decoding, invalid inputs, QR detection, URL/unsupported payloads, duplicate and subtype merging, conflict review, and input-order determinism.

### Backlog audit

- The attached model, classifier, preprocessing, language-inference, and pure-logic test prompts were already implemented in more mature forms and were not duplicated.
- Contact writes and camera UI remain host-owned and excluded by the permanent package boundary.
- Future back-scan work should add an external aggregate-only real-device acceptance harness before expanding supported barcode semantics.

## Session 2026-08-28 — Conditional dual-pass experiment (completed)

Goal: evaluate a default-off second-request fast path without weakening the shipped dual-pass default or using unavailable private photos.

### What changed

1. **Fail-closed eligibility**: a primary pass may skip only with at least two complete strict-contact families, all-line confidence at or above 0.82, Latin-only single-script content, simple single-column bounded geometry, no strict alternative/country-code conflict, and no base review warning.
2. **Structural rejection**: full-image fallback and every targeted re-recognition request always retain dual-pass. Low confidence, mixed script, multiple columns, crop-edge contact, conflicting alternatives, insufficient contacts, and review warnings also retain the existing request and merge.
3. **Redacted diagnostics v2**: fixed reason counts and skip totals are additive and schema-1 diagnostics decode with empty disabled defaults. No triggering OCR value, confidence, geometry, image, or path is exposed.
4. **Paired benchmark v2**: shipped and conditional scans alternate order per scene. Reports include aggregate skip reasons, total second-request delta, exact/review pair changes, and p50/p95 deltas.
5. **Evidence**: three measured runs kept golden 150/150 and stress 72/72 exact with zero review changes. The experiment saved 72 and 39 secondary requests respectively; golden p50/p95 changed by -20.6/-4.1 ms and stress by -61.9/-69.2 ms.

### Decision

Keep the implementation as a default-off experiment only. Do not enable it by default or claim production improvement until the external private real-photo holdout passes. The existing shipped OCR path remains unchanged.

## Session 2026-08-28 — Spaced email OCR recovery (completed)

Goal: continue public performance work while the original private photos are unavailable, and eliminate the single shared stress-corpus contact failure without changing OCR policy.

### What changed

1. **Root cause isolated**: the strongest default-threshold blur case produced a complete email with spaces around `@`. Email extraction missed it and website extraction promoted the domain fragment; targeted ON and OFF failed identically.
2. **Narrow normalization**: base extraction accepts optional whitespace around `@` only inside complete email syntax, normalizes the compact value, and retains the raw spaced reading as `originalValue`. The website guard now recognizes a spaced preceding `@`.
3. **False-positive guards**: prose without a dotted domain stays unresolved, while a separate explicit website on the same OCR line remains classified.
4. **Stronger stress gate**: the paired benchmark test now requires 24/24 exact and zero false clears in both configurations.
5. **Updated evidence**: a repeat measured 24/24 on both paths with no paired accuracy difference. Targeted execution remained 75% and substantially slower, so no OCR threshold or default changed.

The prior private holdout attempt remains unavailable because only one of the original nineteen transient attachments is still accessible. No partial private corpus or inferred ground truth was created.

## Session 2026-08-28 — Private targeted re-recognition holdout runner (completed)

Goal: make natural low-confidence real-photo evidence measurable without committing or reporting private source identity and without changing recognition policy.

### What changed

1. **External-only corpus boundary**: `card-field-private-benchmark` reads `manifest.json` and relative images only from `PRIVATE_CARD_CORPUS_ROOT`. Absolute/traversal paths, duplicate references, symlink escape, unknown fields, and unavailable files fail closed; errors are generic.
2. **Aggregate paired evidence**: every case runs at least three repetitions with alternating ON/OFF order. Reports include exact/review rates, field support, false clears, isolation/fallback counts, request and latency distributions, recoveries/regressions, and deterministic case-cluster bootstrap intervals without source identifiers or OCR content.
3. **Fixed shipped policy**: the external schema cannot configure confidence. Runs use the production `0.35` targeted threshold, and private evaluation cannot mutate scanner defaults.
4. **Fail-closed decision gate**: fewer than four naturally executing cases is insufficient. Any field regression or excessive p95 increase rejects a change. A clean result permits human review only.
5. **Current result**: no private corpus is configured in this environment. The CLI emits a redacted successful skip, so real-photo evidence remains unavailable rather than being inferred from synthetic data.

### Verification

Five new tests cover redaction, deterministic order-independent bootstrap, decision gates, filesystem boundaries, and a transient fictional image run with three paired repetitions. `./Scripts/check-repository.sh` passes with 147 tests; public-alpha base, column-aware, and strict-field configurations retain zero false positives and zero false negatives. The private CLI help and missing-corpus skip paths also pass. No private result was fabricated.

## Session 2026-08-28 — Targeted re-recognition stress evidence (completed)

Goal: measure a previously unexercised OCR stage without changing recognition policy or weakening the 50-case golden baseline.

### What changed

1. **Separate 12 × 2 stress corpus**: a versioned fictional manifest adds contact-only small text, blur, low contrast, glare, shadow, mixed script, isolation success, and forced full-image fallback. Existing golden content and expectations are unchanged.
2. **Transparent threshold cohorts**: four cases use the shipped `0.35` confidence limit, eighteen use a benchmark-only `1.0` calibration limit to guarantee measurable stage execution, and two use a zero-threshold non-execution control. Reports expose only cohort counts.
3. **Paired aggregate evaluator**: targeted enabled/disabled scans alternate execution order and report field-family exact rates, false clears, review changes, recovered/regressed fields, request counts, and total/targeted p50/p95. OCR values, confidence, images, paths, tags below a four-sample boundary, and case identifiers are absent.
4. **Safety tests**: stress rendering and aggregation are deterministic; pair order does not change results; diagnostics OFF/ON preserves tokens, fields, and card-region selection; calibrated cases execute, controls do not; isolation and fallback paths are both covered.
5. **Finding**: one warmup plus one measured run produced 23/24 exact cases on both paths, zero recoveries, zero regressions, and zero review changes. Enabled execution occurred in 18/24 cases, increased total p50 from 133 ms to 341 ms, and added two targeted requests at p50/p95. Shipped-threshold stress cases did not execute.

### Decision

- Keep the shipped targeted re-recognition policy and threshold unchanged.
- Do not promote the calibration threshold; it is measurement scaffolding only.
- The next evidence should be a private, aggregate-only real-photo holdout containing natural `≤0.35` confidence cases. Synthetic forced execution does not establish recovery value.

## Session 2026-08-28 — Golden corpus expansion and diagnostics baseline (completed)

Goal: turn the five-scene smoke set into a useful synthetic regression/measurement corpus and use the redacted diagnostics contract to bound the next adaptive OCR experiment without changing recognition policy.

### What changed

1. **Versioned 25 × 2 corpus**: schema v2 separates four fictional content profiles from 25 layout templates. Each layout expands into exactly two deterministic variants, for 50 cases spanning multilingual, layout, lighting, blur, crop, QR, overlap, background, and card-isolation tags. Images remain runtime-only Core Text/Core Graphics renders.
2. **Shared benchmark module**: `AppleVisionBenchmarking` owns manifest decoding, deterministic rendering, exact-field comparison, aggregate distributions, tag summaries, and the four non-mutating configurations. Small tag groups below four samples are omitted from detailed output.
3. **Aggregate-only CLI**: `card-field-benchmark` separates warmup from measured runs and serializes only corpus counts/tags, field parity/review rates, p50/p95 timing, Vision request counts, execution rates, and fallback rates. It has no case identifier, OCR/token/confidence, image, or path field.
4. **Expanded gates**: all 50 cases pass the shipped default, column-aware, and strict-field configurations. Diagnostics OFF/ON preserve identical token, field, and card-region results for all cases. Manifest hygiene, deterministic rendering, report redaction, configuration minimality, percentile determinism, and input-order independence have direct tests.
5. **Measured conclusion**: one warmup plus one measured run kept 50/50 exact cases under default, while disabling dual-pass reduced median latency and one text request but fell to 46/50. Targeted re-recognition executed zero times, so its isolated value/cost is insufficiently exercised. No adaptive gate was implemented.

### Next decision boundary

- Do not make single-pass the default from synthetic timing; the observed 8% exact-case loss is a hard regression.
- The only justified next experiment is a default-OFF, fail-closed dual-pass skip gated by complete primary-pass contact syntax and absence of low-confidence/multilingual evidence, evaluated first on a private real-photo holdout.
- Add targeted-re-recognition-positive private cases before drawing conclusions about that stage.

## Session 2026-08-27 — Adaptive OCR diagnostics integration (completed)

Goal: integrate the observation layer from the historical adaptive branch on current `scanTokens`/column-aware/strict-field architecture without adopting an unmeasured recognition policy.

### What changed

1. **Shared opt-in contract**: `AppleVisionDiagnosticsOptions` defaults to disabled. Both `AppleVisionScanResult` and `AppleVisionTokenScanResult` add an optional versioned, Codable `AppleVisionScanDiagnostics` payload; disabled calls return `nil` and allocate no instrumentation object.
2. **Current-pipeline instrumentation**: the shared recognition path measures fixed stages and counts rectangle, saliency, primary/secondary text, and targeted text requests. It reports configured/executed dual-pass and targeted refinement plus card-isolation attempt/success/fallback flags. Repeated candidate requests aggregate deterministically.
3. **Privacy boundary**: diagnostics contain only fixed identifiers, durations, counts, and booleans. OCR text, alternatives, token values/confidence, geometry, images, paths, and arbitrary metadata are excluded by design and contract tests. No logging or persistence was added.
4. **Parity before policy**: no adaptive gating or alternative promotion was integrated. The existing OCR path, reusable token API, column-aware classifier, and strict-field corrector remain unchanged. All five golden scenes compare OFF versus ON and require identical tokens, fields, and region selection; token-only scanning has an independent parity/request-count test.
5. **Historical audit**: the 10 commits on `codex/adaptive-ocr-diagnostics` were reviewed without cherry-picking or modifying its worktree. Only diagnostics concepts were reimplemented; eight evolving adaptive-policy commits were deferred until current measurements justify a strategy. The commit-by-commit table lives in `Docs/ADAPTIVE_OCR_DIAGNOSTICS.md`.

### Verification

```sh
swift test --no-parallel
swift run card-field-eval Fixtures/Synthetic/public-alpha.json
./Scripts/check-repository.sh
```

The base, column-aware, and strict-field public-alpha configurations retain zero false positives and zero false negatives through their regression tests. Diagnostics OFF/ON preserve all five golden results and the provider-neutral token-only result.

### Remaining work

- Collect stage/request distributions on the expanded synthetic and private aggregate-only corpora before proposing conditional dual-pass.
- Treat overlapping stage spans correctly: targeted re-recognition can contain primary/secondary request time, so only total duration is end-to-end latency.
- Keep any future adaptive policy independently opt-in and compare accuracy, review rate, p50/p95, and request savings against the unchanged default.
- Expand the five-scene golden regression set before using it as a performance corpus.

## Session 2026-08-27 — Strict-field OCR alternative correction (completed)

Goal: allow lower-ranked OCR readings to recover strict contact syntax without changing default classification or letting alternatives influence free-text fields.

### What changed

1. **Independent opt-in**: `StrictFieldCorrectionOptions` defaults to disabled and adds no output field, warning case, schema, or contract-version change. Disabled mode remains byte-for-value equivalent to the legacy classifier.
2. **Narrow syntax scope**: only email, explicitly prefixed website (`http`, `https`, or `www`), and phone-shaped lines can inspect alternatives. Name, title, organization, department, and address paths use original tokens plus legacy contact-consumption and email-hint state.
3. **Fail-closed selection**: a replacement requires exactly one normalized valid alternative, a syntax-score margin of at least `0.30`, and token confidence of at least `0.55`. Candidate array order has no effect. Invalid readings are ignored and duplicate renderings collapse by normalized value.
4. **Conflict behavior**: a valid primary is never replaced. Competing valid values, low confidence, or insufficient margin retain the original and append `reviewRecommended`; phone conflicts also append `ambiguousPhoneNumber`. Phone alternatives must preserve the printed mobile/work/fax subtype, and local-versus-international variants are never silently reconciled.
5. **Regression coverage**: tests cover disabled parity, email/website/phone recovery, duplicates, competing values, valid-primary preservation, invalid candidates, subtype changes, low confidence, country-code conflicts, free-text isolation, input-order determinism, public-alpha parity, and all five golden scenes with the option enabled.

### Verification

```sh
swift test --no-parallel             # 129 passed
swift run card-field-eval Fixtures/Synthetic/public-alpha.json
swift run card-field-eval Fixtures/Synthetic/phase1.json
./Scripts/check-repository.sh
```

The base, column-aware, and strict-field public-alpha runs retain zero false positives and zero false negatives. The golden suite passes with strict-field correction both off and on.

### Remaining work

- Expand five generated golden scenes toward at least 25 layouts with two deterministic variants each before treating them as a performance corpus.
- Rebase and audit the separate adaptive OCR diagnostics branch before integrating latency work; it predates the reusable token API, column-aware classifier, and strict-field corrector.
- Measure correction acceptance and unnecessary-review rates on a private fictionalized or transient real-photo corpus before recommending opt-in for production.
- Keep real-photo and physical-device evaluation private and report aggregates only.

## Session 2026-08-27 — Column-aware phone label linking (completed)

Goal: use `LayoutAnalyzer` output conservatively when reading order separates a visible phone label from its value, without changing the default classifier result.

### What changed

1. **Safe opt-in API**: `ColumnAwareClassifierOptions` defaults to disabled. `classifyWithDiagnostics` returns the regular `CardFieldResult` plus per-call diagnostics without mutable classifier state; the existing `classify` signature and default behavior are unchanged.
2. **Real column evidence**: candidate scoring consumes `LayoutAnalyzer.rows` and `LayoutAnalyzer.columns`, distinguishes same-row cross-column links from vertically aligned adjacent rows, applies deterministic thresholds, and fails closed when layout confidence is low.
3. **Phone-only v1 scope**: the additive pass recovers only mobile/work/fax values missed by the legacy pass. It never removes or rewrites an existing value, does not invent a country prefix, suppresses duplicates, and routes tied candidates to `ambiguousPhoneNumber` plus `reviewRecommended`.
4. **Regression coverage**: active-path tests cover disabled parity, cross-column and vertical recovery, Korean/English subtype labels, multiple labels, conflicts, low-confidence and invalid-geometry fallback, input-order determinism, duplicate suppression, local/international normalization, diagnostics JSON, public-alpha parity, and the two-column golden scene.
5. **Compatibility**: no output-contract enum or schema change was required. Hosts opt in by injecting a `CardFieldClassifier` configured with `ColumnAwareClassifierOptions(mode: .enabled)` into `AppleVisionScanner`.

### Verification

```sh
swift build
swift test --no-parallel             # 113 passed
swift run card-field-eval Fixtures/Synthetic/public-alpha.json
swift run card-field-eval Fixtures/Synthetic/phase1.json
swift run card-field-scan --help
./Scripts/check-repository.sh
```

Both evaluators retain zero false positives and zero false negatives. The public-alpha corpus is also evaluated with column-aware mode enabled in the test suite.

### Remaining work

- Expand five generated golden scenes toward at least 25 layouts with two deterministic variants each before treating them as a performance corpus.
- Evaluate `OCRToken.alternatives` for syntax-valid strict-field recovery without changing the token contract.
- Rebase and audit the separate adaptive OCR diagnostics branch before integrating latency work; it predates the reusable token API and this classifier branch.
- Keep real-photo and physical-device evaluation private and report aggregates only.

## Session 2026-08-26 — Golden-scene regression corpus (completed)

Goal: close the first item from the open-work list by making preprocessing/recognition changes measurable per change. No commits or pushes were made in this session.

### What changed

1. **Manifest-driven synthetic scenes**: `Fixtures/GoldenScenes/manifest.json` describes five scenes (canvas, optional card quad on a dark backdrop, text lines with normalized positions/font sizes, recognition languages, region mode, expected fields). Images are *not* committed — scenes render deterministically with Core Text at test time, keeping the repo free of binary artifacts while preserving the golden-corpus property (expected fields are pinned; any pipeline change that shifts recognized output fails loudly).
2. **Scene coverage**: straight full-bleed English card; skewed card inside a dark scene through automatic region isolation; Hangul card (ko-KR + en-US auto-detect) exercising font fallback and Korean phone normalization (`010-0000-0001` → `01000000001`); compact low-contrast card (900×520, gray-on-gray) exercising preprocessing upscale/contrast; two-column layout seeding the upcoming column-aware classifier work.
3. **Test support**: `Tests/AppleVisionAdapterTests/GoldenSceneSupport.swift` — `GoldenScene` decoder, `GoldenSceneRenderer` (deterministic Core Text), `GoldenFieldComparator` (whitespace-stripped case-folded set matching per field, with digit-only fallback matching for phone fields so formatting variance does not mask real regressions).
4. **Tests** (`GoldenSceneRegressionTests.swift`, 98 total now): full-pipeline reproduction of every expected field plus region-mode conformance; repeated-scan stability guard over the Hangul scene (highest provider variance risk); manifest hygiene (unique `golden-*` identifiers, bounded geometry, known field keys, fictional namespaces — emails/websites under `.example`/`example.*`, phones containing `555` or `010` prefixes).
5. Calibration was performed empirically: a temporary diagnostic dump confirmed all five scenes classify exactly as authored before expectations were frozen; the diagnostic file was removed after calibration.

### Commands executed (all passing)

```sh
swift build
swift test                       # 98 passed
swift run card-field-eval Fixtures/Synthetic/public-alpha.json   # FP/FN = 0 on every field
swift run card-field-eval Fixtures/Synthetic/phase1.json         # exit 0
swift run card-field-scan --help # flags listed
swift format lint --recursive --strict Sources Tests Package.swift
```

### Remaining risks / notes

- Golden expectations were calibrated on this machine's Vision runtime (revision pinned to 3 in config defaults). Provider-level OCR drift across OS versions may require re-calibrating individual scenes; failures name the scene and field so triage is cheap.
- `Scripts/check-repository.sh` still cannot run here (ripgrep absent); steps above were run individually as in prior sessions.
- Scene rendering relies on system font fallback for Hangul (Helvetica lacks Hangul glyphs). If a future macOS drops the fallback font, only the Korean scene would need a font override in the renderer.

## Session 2026-08-23 — Build restored + generic token-only scanTokens API (completed)

Goal: unblock the SwiftPM build broken by a duplicated adapter file, then expose the existing OCR pipeline as a generic token-only API for non-card documents (a future AnswerSheetFieldKit can consume it). No commits or pushes.

### Duplicate file resolution and recovery path

`Sources/AppleVisionAdapter/AppleVisionAdapter 2.swift` (untracked, 52,370 B, mtime 2026-08-22 13:53, SHA-256 `5597bff1de12c2a9d9478e8af71f912035d6733fd503bd695223f73d64ae3c44`) shadowed the tracked implementation with an older snapshot missing `refinedForTesting`, the `nonisolated(unsafe)` regex statics, the perspective-correction top-up fix, and format normalization — tests reference `refinedForTesting`, so the tracked file was judged canonical. The duplicate was **moved (not deleted)** to `<repository-backups>/AppleVisionAdapter 2.swift` (checksum verified identical after move). Restoring it under `Sources/AppleVisionAdapter` would reintroduce ambiguous-type build failures while both files exist in the target directory.

### What changed

1. **Build normalized**: moving the stale duplicate out fixed the `invalid redeclaration` errors; baseline restored at 87 passing tests before any feature work.
2. **Additive public contract**: `AppleVisionTokenScanResult { tokens: [OCRToken], cardRegionSelection }` — provider-neutral tokens without field classification.
3. **New APIs on `AppleVisionScanner`**: `scanTokens(imageData:orientation:)`, `scanTokens(cgImage:orientation:)`, plus `scanTokensAsync` variants on detached background tasks.
4. **Shared pipeline, zero duplication**: `scan` now routes through the same internal `performTokenRecognition` path as `scanTokens`; classification (`makeResult` → `CardFieldClassifier.classify`) happens only afterwards. Token production, card-region selection, dual-pass merging, targeted re-recognition, and language inference run exactly once per call. `.noRecognizedText` now throws from the shared path (same point in the flow as before).
5. **Tests**: new `Tests/AppleVisionAdapterTests/TokenScanTests.swift` (8 tests, 95 total) covering invariants (non-empty text, confidence range, unit-square boxes), stable positional ids, sync/async parity, repeated-run stability, `scan.tokens == scanTokens.tokens`, CardFieldResult regression guard, independence from classifier failures (failing `CorrectionStore`: `scan` throws `.classificationFailed` while `scanTokens` succeeds), automatic-region isolation via token scanning, full metadata preservation incl. alternatives, legacy JSON decoding, and Vision E2E over synthetic fictional pages.
6. **Docs**: OCR_ADAPTERS.md gained a "Token-only scanning for other documents" section (scan vs. scanTokens table, `cardRegion .disabled` guidance for non-card consumers, host-owned review/storage responsibility, no-persistence/no-network guarantees, fictional-fixture rule). ARCHITECTURE.md mentions the generic entry point.

### Compatibility

No existing public API changed signature or semantics; Relationship Memory and all current callers compile unchanged (87 pre-existing tests pass untouched). `scanTokens` never calls `CardFieldClassifier`, so it cannot emit `.classificationFailed`.

### Commands executed (all passing)

```sh
swift build
swift test                       # 95 passed
swift run card-field-eval Fixtures/Synthetic/public-alpha.json   # FP/FN = 0 on every field (26 fixtures)
swift run card-field-eval Fixtures/Synthetic/phase1.json         # exit 0
swift run card-field-scan --help # flags listed
swift format lint --recursive --strict Sources Tests Package.swift
docc convert (warnings-as-errors) # pass
git diff --check                 # clean
```

### Remaining risks / notes

- `Scripts/check-repository.sh` could not run as-is: ripgrep is absent on this machine and the script fails fast by design. Every step was executed individually instead, with `grep -rEn '(AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'` as the credential-scan equivalent (no matches). Installing rg restores one-command verification.
- E2E token tests render fictional content only ("Practice Worksheet", "Alex Kim", `example.com`, 555 numbers); Hangul rendering relies on Core Text font fallback and assertions are invariant-based, not glyph-exact.
- Provider-level OCR variance across OS/Vision revisions applies to `scanTokens` equally to `scan`.

### Recommended configuration for AnswerSheetFieldKit (future consumer)

```swift
AppleVisionScanConfiguration(
  recognitionLanguages: ["ko-KR", "en-US"],
  automaticallyDetectsLanguage: true,
  cardRegion: AppleVisionCardRegionConfiguration(mode: .disabled),
  preprocessing: AppleVisionPreprocessingConfiguration(),       // enabled
  dualPassRecognition: true,
  performsTargetedReRecognition: true
)
// then scanner.scanTokens(imageData:) / scanTokensAsync(...)
```

This exact configuration is exercised by `TokenScanTests.scanTokensInvariants`. Keep AnswerSheet-specific parsing out of this package; consume `OCRToken` from outside.

## Session 2026-08-22 — Pre-publication verification & audit (completed)

Goal: make the uncommitted OCR improvements GitHub-ready. No commits or pushes were made in this session; results and a suggested commit split are recorded for the maintainer.

### Issues found and fixed

1. **`swift format lint --strict` failures** in `AppleVisionAdapter.swift`, `ImagePreprocessing.swift`, `LayoutAnalyzer.swift`, `OCRUpgradeTests.swift` (semicolons, long lines, indentation, trailing commas, multiline expressions). Fixed by normalizing those four files with `swift format format --in-place`; diff reviewed to confirm whitespace/line-break-only changes with identical semantics.
2. **Missing direct coverage for Vision revision clamping** (`recognitionRevision` 1...3). Added regression test "Recognition revisions are clamped to the supported 1...3 range" (87 tests total now).
3. **Real provider domain in new test fixtures**. Replaced with fictional domains (`example.net`,
   `example.org`, mangled variants like `exampl3.net`) per PRIVACY.md/AGENTS.md rules.
4. **Environment caveat:** `Scripts/check-repository.sh` step at line 30 silently no-ops when `rg` is not installed (command-not-found inside an `if` does not fail under `set -e`). The script still exits 0. Locally verified the credential scan equivalent with `grep -rEn '(AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' .` → no matches. Consider adding a guard such as `command -v rg >/dev/null || { echo "ripgrep required" >&2; exit 1; }`.

### Safety audit of the ten OCR improvements — results

| Audit item | Result |
|---|---|
| `OCRToken.alternatives` legacy decoding | ✅ `decodeIfPresent ?? []` (Contracts.swift:65); regression test decodes JSON without the key |
| Dual-pass merge determinism | ✅ Sequential greedy match with strict-`>` comparison (first index wins ties); leftovers sorted by minY desc then minX; stable for a fixed provider output |
| Strict-syntax keeps raw reading | ✅ `prefersUncorrectedText` gates `mergingLine`; unit + E2E email-exact assertions |
| Targeted re-recognition cannot fail a scan | ✅ All paths guarded; recognition wrapped in `try?`; returns original tokens on any failure |
| Shared CIContext concurrency | ✅ `nonisolated(unsafe)` static let; Apple documents `CIContext` as thread-safe; escape hatch documented in AGENTS.md |
| Vision revision clamp | ✅ Clamped at config init and again in `makeRequest`; now directly tested |
| Saliency never outranks rectangles | ✅ Only consulted when rectangle ranking is empty; confidence capped at 0.75; contact-text evidence gate still required |
| `scanAsync` never blocks the caller | ✅ `Task.detached(priority: .userInitiated)`; CGImage bridged via documented immutable wrapper |
| CardFieldCore stays provider-neutral | ✅ Every core file imports Foundation only |

### Commands executed this session (all passing)

```sh
./Scripts/check-repository.sh    # exit 0 (format lint, build, 87 tests, eval ×2, CLI, docc, schema JSON)
swift build
swift test                       # 87 passed
swift run card-field-eval Fixtures/Synthetic/public-alpha.json   # 26 fixtures, FP/FN = 0 on every field
swift run card-field-scan --help # all five --no-* flags listed
git diff --check                 # clean
grep credential scan             # no matches (see rg caveat above)
```

### Remaining risks

- `rg` absence makes the repository script's credential step a silent no-op (fix suggested above).
- Dual-pass doubles accurate-mode latency by design; hosts needing speed can disable via configuration or CLI flags.
- Provider-level OCR variance across OS/Vision versions remains outside the core determinism guarantee; revision pinning reduces but does not eliminate it.
- E2E rendered-card tests depend on local Vision quality; a future golden-image corpus would make regressions more measurable.

## Session 2026-08-22 — OCR pipeline upgrades (completed)

All ten proposed OCR improvements are implemented, tested (86 tests passing), and documented.

### What changed

| # | Improvement | Where |
|---|---|---|
| 1 | Image preprocessing: upscale to minimum long edge (default 1600px), grayscale, contrast +0.08, unsharp mask | `AppleVisionAdapter/ImagePreprocessing.swift`, config `AppleVisionScanConfiguration.preprocessing` |
| 2 | Multi-candidate readings: up to 3 Vision candidates per line; extras stored in `OCRToken.alternatives` | `AppleVisionAdapter.recognizedLines(candidateCount:)`, `CardFieldCore/Contracts.swift` |
| 3 | Dual-pass language correction: corrected + uncorrected passes merged by geometry; email/phone/URL keep raw text (`prefersUncorrectedText`) | `AppleVisionScanner.recognizeLines`, `mergedLines` |
| 4 | Layout clustering utility: rows via >50% vertical overlap, columns via ≥0.08 horizontal gap; deterministic ordering | `CardFieldCore/LayoutAnalyzer.swift` |
| 5 | Targeted re-recognition: tokens ≤0.35 confidence re-read from a padded, upscaled crop; replaced only when stronger; never fails a scan | `AppleVisionScanner.refineLowConfidenceTokens` (+ geometry helpers) |
| 6 | Script-based token languages: Hangul→ko, Kana→ja, Han→zh, Cyrillic→ru, Latin→en; host hint always wins | `CardFieldCore/LanguageInference.swift`, adapter wiring `infersTokenLanguages` |
| 7 | Card detection hardening: perspective-corrected output upscaled to ≥1400px long edge; attention-saliency fallback candidate (confidence capped 0.75, evidence gate still required) | `perspectiveCorrectedImage(minimumLongEdge:)`, `CardRegionSelector.saliencyCandidate` |
| 8 | Vision revision pinned (config `recognitionRevision`, default 3, clamped 1...3) | `makeRequest` |
| 9 | E2E synthetic-image harness: Core Text-rendered card fronts scanned through the full pipeline (straight + skewed-card scenes) | `Tests/AppleVisionAdapterTests/OCRUpgradeTests.swift` |
| 10 | Async APIs: `scanAsync(imageData:)` / `scanAsync(cgImage:)` on background tasks | `AppleVisionScanner` extension |

Code-quality fixes bundled in: process-wide shared `CIContext`, precompiled Swift Regex in `CardTextEvidence`.

### Behavioral notes for reviewers

- Defaults are ON for preprocessing/dual-pass/re-recognition/language inference; each is individually disableable (CLI flags and configuration).
- Latency roughly doubles with dual-pass on accurate mode — intentional tradeoff, documented.
- `OCRToken` gained `alternatives: [String]`; legacy JSON without the key decodes as `[]`. Classification still consumes only `text`.
- Prose keeps the *corrected* reading; strict syntax keeps the *raw* reading. This is deliberate — see test "Strict-syntax lines keep the uncorrected reading".

### Verification performed

```sh
swift build        # clean
swift test         # 86 passed
swift run card-field-scan --help   # flags listed
```

E2E tests render fictional cards ("Alex Kim", `alex.kim@example.com`, `+1 202 555 0147`) locally with Core Text; no real PII anywhere.

### Open work / suggested next steps (priority order)

1. **Golden-image regression corpus** — expand the E2E renderer into a fixture directory (JSON manifest + generated images) so preprocessing/recognition changes are measurable per change.
2. **Column-aware classifier evidence** — feed `LayoutAnalyzer` output into label–value association (e.g., right-column phone under left-column name) instead of reading-order adjacency only.
3. **Alternatives-driven correction** — let the classifier pick an `alternatives` reading when it validates against field syntax (e.g., `example.con` → `example.com`); requires additive contract thinking but no breaking change since classification can stay text-only.
4. **Per-field latency budget** — optional fast path that skips dual-pass when preprocessing alone yields high-confidence strict-syntax lines.
5. **Windows/Linux provider adapters** — contract unchanged; see Docs/OCR_ADAPTERS.md.

### Environment notes

- macOS runner required for adapter/E2E tests (Vision).
- If Vision behaves differently across OS versions, check `recognitionRevision` first; core determinism claims are unaffected either way.

## How to use this file

1. Read the newest session entry before starting work.
2. Check "Open work" before proposing new features.
3. After finishing: add a new entry above, move completed items out of "Open work", run full verification, and note anything surprising.
