# Security Policy

## Supported versions

Until `1.0.0`, security fixes target the current default branch and the latest tagged release. Older
pre-release lines do not receive routine backports.

## Reporting a vulnerability

Do not open a public issue for a vulnerability, credential, or personal-data exposure. Use [GitHub private vulnerability reporting](https://github.com/megabrain11/BusinessCardFieldKit/security/advisories/new).

Include reproduction steps using synthetic data only. Never attach a real card image, OCR result, credential, or personal correction file.

If a credential or personal-data exposure has already reached git history, identify the affected
path and commit without repeating the exposed value. Maintainers will coordinate revocation and
history remediation privately.

## Security properties

The core has no network client, telemetry, image access, or automatic persistence. It processes caller-provided values in memory. Hosts remain responsible for data access, encryption, retention, deletion, and consent.
