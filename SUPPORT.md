# Support

BusinessCardFieldKit is pre-release open-source software. Maintainer support is best-effort, with no guaranteed response or resolution time.

## Before asking for help

Use the latest tagged release. When reproducing an unreleased fix, identify the exact default-branch
commit. Review the [README](README.md) and [DocC catalog](Sources/CardFieldCore/CardFieldCore.docc/CardFieldCore.md), then run:

```sh
swift test --no-parallel
Scripts/check-repository.sh
```

Reproduce the problem with the smallest possible fictional fixture. Never share a real business-card image, raw production OCR, personal correction file, or contact value.

## Where to ask

- Use GitHub Issues for reproducible bugs and narrowly scoped feature requests after the repository is published.
- Use a GitHub Discussion, if enabled, for integration questions and broader design proposals.
- Follow [SECURITY.md](SECURITY.md) for vulnerabilities, credentials, or accidental personal-data exposure. Do not report those in a public issue.

Include the package version or commit, Swift and Xcode versions, target platform, minimal synthetic input, actual result, expected result, and relevant test output. For classification reports, include confidence, evidence, warnings, and source-token geometry when safe.

## Supported versions and platforms

Until `1.0.0`, only the latest tagged release and the current default branch are supported; older
pre-release lines do not receive routine backports. The package currently targets Swift 6.0 or
later, macOS 13 or later, and iOS 17 or later. `CardFieldCore` is provider-neutral;
`AppleVisionAdapter` additionally requires Apple Vision.

## Scope of support

Support covers the public contracts, deterministic classifier, rule packs, included adapters, sanitizer, schemas, and synthetic evaluation tools. Camera behavior, OCR-provider quality, storage, contact persistence, identity resolution, synchronization, and Relationship Memory product behavior remain the responsibility of the host application.
