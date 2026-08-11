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

Requirements: Swift 6.0 or later on a supported Apple platform.

```sh
swift build
swift test
swift format lint --recursive --strict Sources Tests Package.swift
swift run card-field-eval Fixtures/Synthetic/phase1.json
```

Run `Scripts/check-repository.sh` for the complete local check.

## Rules and fixtures

Every classification change needs a synthetic regression test. New locale or industry terms should be narrowly scoped, versioned, documented, and covered by both a positive case and a false-promotion case where relevant.

Repository artifacts must be English. User-facing integrations should keep copy localization-ready.

## Pull requests

Explain the problem, privacy review, contract impact, rule-version impact, and test evidence. Keep unrelated changes separate. API-breaking changes require an architecture discussion before implementation.
