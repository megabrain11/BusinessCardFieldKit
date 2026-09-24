# Contributing

Thank you for improving BusinessCardFieldKit.

## Privacy gate

Before opening an issue or pull request:

1. Do not include a real business-card image or raw OCR output.
2. Do not include a real name, email, phone number, address, social handle, or private correction.
3. Use `.example` domains and clearly fictional values.
4. Prefer sanitizer placeholders in structural reports.
5. Review every attachment and diff manually.

Submissions that contain personal data will be removed from consideration and may need repository-history remediation.

## Development

Requirements: Swift 6.0 or later on a supported Apple platform, plus [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) for the credential scan in `Scripts/check-repository.sh`.

```sh
swift build
swift test --no-parallel
swift format lint --recursive --strict Sources Tests Package.swift
swift run card-field-eval Fixtures/Synthetic/phase1.json
swift run card-field-eval Fixtures/Synthetic/public-alpha.json
```

Run `Scripts/check-repository.sh` for the same complete check used by CI. It also validates DocC,
JSON syntax, CLI entry points, deterministic synthetic benchmark paths, and credential patterns. The
script requires Xcode's `docc` command and fails fast with a clear message when `rg` is missing.

## Rules and fixtures

Every classification change needs a synthetic regression test. New locale or industry terms should be narrowly scoped, versioned, documented, and covered by both a positive case and a false-promotion case where relevant.

Repository artifacts must be English. User-facing integrations should keep copy localization-ready.

## Pull requests

Explain the problem, privacy review, contract impact, rule-version impact, and test evidence. Keep unrelated changes separate. API-breaking changes require an architecture discussion before implementation.

Maintainers retain approval over architecture boundaries, privacy-sensitive changes, experimental
default changes, merges, tags, and releases. AI-assisted contributions are welcome, but a human
contributor must review the resulting diff, synthetic data, and verification output before opening
a pull request. AI contributors should read [AGENTS.md](AGENTS.md) before changing the repository.

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Use the issue templates for
bugs, feature requests, and rule-pack proposals; report security or privacy vulnerabilities through
the private channel in [SECURITY.md](SECURITY.md).
