# Privacy

Business cards contain personal data. BusinessCardFieldKit is designed to minimize collection and prevent accidental sharing.

## Default behavior

- All classification is local and deterministic.
- The package contains no networking, telemetry, analytics, remote logging, or upload code.
- The core receives text observations, not card images.
- The core does not persist OCR text or results.
- Personal corrections remain local unless a host explicitly exports them.
- Back-side analysis and image storage are outside the package.

## Prohibited repository content

Never commit or attach:

- Real business-card images
- Real names copied from physical cards
- Real email addresses, phone numbers, or street addresses
- Raw OCR output from a real card
- Private correction files
- API keys, tokens, credentials, or production datasets

Use clearly fictional values and reserved domains such as `.example`.

## Personal corrections

Prefer narrow reusable rules over full records. A domain-to-organization rule is safer than memorizing a person's name, title, phones, email, and address. Hosts control storage, encryption, backup, retention, and deletion. `LocalJSONCorrectionStore` reads only the explicit local URL supplied by the host.

## Community drafts

`ContributionSanitizer` produces a reviewable structural draft using placeholders such as `<PERSON_NAME>`, `<JOB_TITLE>`, `<ORGANIZATION>`, `<MOBILE_PHONE>`, `<EMAIL>`, `<WEBSITE>`, and `<ADDRESS>`. Unclassified text becomes `<UNCLASSIFIED>`. Correction match and replacement values are removed.

The sanitizer never uploads. Before opening an issue or pull request, review the draft and confirm that no image, OCR text, personal value, metadata, or local correction file is attached.

## Host responsibilities

Hosts must obtain appropriate consent, keep OCR suggestions editable, protect any retained images or results, implement deletion, avoid automatic identity merges, and require review before saving or acting on a field.
