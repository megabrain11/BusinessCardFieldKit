# Local Image Scanning

`card-field-scan` is a local Apple-platform command for testing the complete image-to-fields
pipeline. It reads each explicitly supplied image, isolates one likely foreground business card,
runs Apple Vision OCR, classifies the recognized text, and writes JSON to standard output.

```sh
swift run card-field-scan ./card-front.jpg
swift run card-field-scan --language ko-KR --language en-US ./cards/*.jpg
```

The command does not copy images, save results, log OCR text, or make network requests. Shell
redirection is an explicit host or user decision. Output contains structured fields by default;
raw OCR tokens appear only with `--include-tokens`.

## Foreground-card isolation

Automatic isolation is enabled by default. The adapter:

1. Detects a bounded set of plausible business-card quadrilaterals.
2. Perspective-corrects only the strongest geometric candidates.
3. Runs local OCR on each bounded candidate.
4. Selects the candidate with the strongest combined geometry and contact-text evidence.
5. Falls back to full-image OCR when no usable card region is found.

Every successful CLI item reports `cardRegion.mode` as `isolated`, `fullImageFallback`, or
`disabled`. An isolated item also reports the normalized source-image bounding box and selection
scores. Use `--no-card-isolation` to compare against complete-image OCR.

Isolation chooses one card. It does not enumerate every card in a photograph. A host that wants
multi-card capture should ask the user to confirm each detected card or submit separate crops.

## Review-first CRM use

Treat every field as a suggestion. In particular, do not automatically save or merge a contact
when the result contains `identityConflict`, `reviewRecommended`, `ambiguousPersonName`,
`ambiguousPhoneNumber`, or `lowConfidenceFields`.

Exact shared email or phone values can help a host propose that two scans are different sides of
the same card, but identity matching and contact merging remain host-owned CRM behavior. The
package never performs those actions.

## Known limits

- Icon-only phone labels remain unresolved because OCR observations contain no icon semantics.
- QR payload decoding is not part of the text scanner.
- Apple Vision OCR can vary by operating-system and Vision revision.
- A heavily occluded card or a scene containing several equally complete cards may require a user
  crop or explicit confirmation.
- Organization hierarchies, brands, legal entities, and multiple simultaneous roles may require
  review even when their source text is recognized correctly.
