# CLAUDE.md

Read `AGENTS.md` first — it contains the authoritative project brief, hard rules, build commands, architecture map, and design decisions that apply to every agent in this repository.

Quick reminders specific to working here:

- Run `swift test` before declaring anything done; 87+ tests must pass on macOS.
- `CardFieldCore` must stay free of Vision/CoreImage/UIKit imports. Image-domain code belongs in `AppleVisionAdapter`.
- Never add real names, emails, phone numbers, or card images to tests, fixtures, or docs. Fictional data only (`example.com`, `555` numbers).
- Contract types are versioned: extend additively with backward-compatible decoding (see `OCRToken.alternatives`).
- When you finish a significant change, update `Docs/AI_COLLABORATION.md` so the next session (human or agent) starts from current state.
