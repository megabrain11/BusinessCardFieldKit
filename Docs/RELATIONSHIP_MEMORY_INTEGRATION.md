# Relationship Memory Integration

Relationship Memory can adopt the package later without moving image or CRM behavior into the library.

1. Add this package as a local or approved remote Swift Package dependency.
2. Keep camera, PhotosUI, image resizing, front/back pairing, and protected image persistence in the host app.
3. Run the existing Vision recognition request only for the front image.
4. Convert `VNRecognizedTextObservation` values with `AppleVisionAdapter`.
5. Classify with `CardFieldClassifier`, optionally loading local corrections and approved packs.
6. Map the reviewed `CardFieldResult` fields to the host draft model.
7. Preserve confidence, evidence, alternatives, and source tokens in the review experience where useful.
8. Never auto-merge a person or persist a suggested field without host review policy.

An example conversion appears in `Examples/Integration/RelationshipMemory.swift`.

The host retains ownership of business-card images, optional back images, deletion lifecycle, person records, provenance, localization, and UI. No integration change is included in this repository.
