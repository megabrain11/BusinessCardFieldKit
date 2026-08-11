# Security Policy

## Supported versions

Until the first stable release, only the latest commit on the default branch is supported.

## Reporting a vulnerability

Do not open a public issue for a vulnerability, credential, or personal-data exposure. Use [GitHub private vulnerability reporting](https://github.com/megabrain11/BusinessCardFieldKit/security/advisories/new).

Include reproduction steps using synthetic data only. Never attach a real card image, OCR result, credential, or personal correction file.

## Security properties

The core has no network client, telemetry, image access, or automatic persistence. It processes caller-provided values in memory. Hosts remain responsible for data access, encryption, retention, deletion, and consent.
