#!/bin/sh
set -eu

swift format lint --recursive --strict Sources Tests Package.swift
swift build
swift test
swift run card-field-eval Fixtures/Synthetic/phase1.json >/dev/null
swift run card-field-eval Fixtures/Synthetic/public-alpha.json >/dev/null
swift run card-field-scan --help >/dev/null

docc_validation_dir=$(mktemp -d)
trap 'rm -r "$docc_validation_dir"' EXIT
swift build --target CardFieldCore \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir \
    -Xswiftc "$docc_validation_dir"
xcrun docc convert Sources/CardFieldCore/CardFieldCore.docc \
    --additional-symbol-graph-dir "$docc_validation_dir" \
    --fallback-display-name CardFieldCore \
    --fallback-bundle-identifier dev.businesscardfieldkit.CardFieldCore \
    --fallback-bundle-version 0.1.0 \
    --warnings-as-errors \
    --diagnostic-level warning \
    --output-path "$docc_validation_dir/CardFieldCore.doccarchive"

for file in Schemas/*.json Rules/*.json Fixtures/Synthetic/*.json Examples/Corrections/*.json; do
    python3 -m json.tool "$file" >/dev/null
done

if rg -n --hidden --glob '!LICENSE' --glob '!.git/**' \
    '(AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' .; then
    echo "Potential credential material found." >&2
    exit 1
fi
