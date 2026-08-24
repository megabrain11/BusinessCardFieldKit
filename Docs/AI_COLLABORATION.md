# AI Collaboration Handoff

Living document for humans and AI agents (Codex, Claude Code, others). Update the relevant section when you finish significant work. Newest entries at the top.

## Session 2026-08-23 — Build restored + generic token-only scanTokens API (completed)

Goal: unblock the SwiftPM build broken by a duplicated adapter file, then expose the existing OCR pipeline as a generic token-only API for non-card documents (a future AnswerSheetFieldKit can consume it). No commits or pushes.

### Duplicate file resolution and recovery path

`Sources/AppleVisionAdapter/AppleVisionAdapter 2.swift` (untracked, 52,370 B, mtime 2026-08-22 13:53, SHA-256 `5597bff1de12c2a9d9478e8af71f912035d6733fd503bd695223f73d64ae3c44`) shadowed the tracked implementation with an older snapshot missing `refinedForTesting`, the `nonisolated(unsafe)` regex statics, the perspective-correction top-up fix, and format normalization — tests reference `refinedForTesting`, so the tracked file was judged canonical. The duplicate was **moved (not deleted)** to `/Users/yoon/Documents/BusinessCardFieldKit-backups/AppleVisionAdapter 2.swift` (checksum verified identical after move). Restore with: `mv "/Users/yoon/Documents/BusinessCardFieldKit-backups/AppleVisionAdapter 2.swift" "Sources/AppleVisionAdapter/AppleVisionAdapter 2.swift"` — but do not: it reintroduces ambiguous-type build failures while both files exist in the target directory.

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
3. **Real provider domain in new test fixtures** (`gmail.com`). Replaced with fictional domains (`example.net`, `example.org`, mangled variants like `exampl3.net`) per PRIVACY.md/AGENTS.md rules.
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
