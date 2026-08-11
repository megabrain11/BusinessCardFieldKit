# Rule Packs

Rule packs are versioned JSON vocabularies for a locale or industry. They are decoded as `RulePack` and passed to `CardFieldClassifier(rulePacks:)`.

Required metadata:

- `schemaVersion`: currently `1.0`
- `identifier`: stable reverse-domain identifier
- `version`: semantic version
- `priority`: integer ordering value

A pack may declare `locale`, `industry`, or both. Vocabulary fields cover organization suffixes and terms, job titles, departments, phone labels, addresses, and slogans. Packs are additive. If two phone labels conflict, the later pack in priority and identifier order wins.

Keep entries narrow. Short terms can create false positives across languages. Add a synthetic regression fixture for every new term and prove that names and slogans are not promoted incorrectly.

Validate format against `Schemas/rule-pack.schema.json`. Examples live in `Rules/`.
