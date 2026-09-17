#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
SIGNED_APP="$PWD/build/Sin AI Prompt.app"
SIGNING_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sinaiprompt-signing.XXXXXX")
trap 'rm -rf "$SIGNING_TEST_DIR"' EXIT

codesign --verify --strict "$SIGNED_APP"
codesign --display -r- "$SIGNED_APP" 2>/dev/null | sed 's/^designated => //' > "$SIGNING_TEST_DIR/original.req"
if [[ ! -s "$SIGNING_TEST_DIR/original.req" ]] || /usr/bin/grep -q '^cdhash ' "$SIGNING_TEST_DIR/original.req"; then
  print -u2 'FAIL: permission persistence requires certificate signing, not a per-build code-hash identity.'
  exit 1
fi
ORIGINAL_HASH=$(codesign --display --verbose=4 "$SIGNED_APP" 2>&1 | sed -n 's/^CDHash=//p')
VARIANT_APP="$SIGNING_TEST_DIR/Changed.app"
ditto "$SIGNED_APP" "$VARIANT_APP"
printf 'Changed build identity fixture\n' > "$VARIANT_APP/Contents/Resources/signing-test.txt"
./scripts/sign-app.sh "$VARIANT_APP"
CHANGED_HASH=$(codesign --display --verbose=4 "$VARIANT_APP" 2>&1 | sed -n 's/^CDHash=//p')
[[ -n "$ORIGINAL_HASH" && -n "$CHANGED_HASH" && "$ORIGINAL_HASH" != "$CHANGED_HASH" ]]
codesign --display -r- "$VARIANT_APP" 2>/dev/null | sed 's/^designated => //' > "$SIGNING_TEST_DIR/changed.req"
cmp "$SIGNING_TEST_DIR/original.req" "$SIGNING_TEST_DIR/changed.req"
codesign --verify --strict -R "$SIGNING_TEST_DIR/original.req" "$VARIANT_APP"
codesign --verify --strict -R "$SIGNING_TEST_DIR/changed.req" "$SIGNED_APP"
print 'PASS: changed app contents retain the same signing identity and satisfy both designated requirements'
