#!/bin/zsh
set -euo pipefail

APP_TO_SIGN=${1:?Pass the application bundle to sign}
SIGNING_IDENTITY=${SIN_CODE_SIGN_IDENTITY:-}
if [[ -z "$SIGNING_IDENTITY" ]]; then
  # Use an existing certificate and private key. Never create or import keys.
  SIGNING_IDENTITIES=("${(@f)$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[[:digit:]]+\) ([[:xdigit:]]{40}) ".*"$/\1/p')}")
  if (( ${#SIGNING_IDENTITIES} != 1 )) || [[ -z "${SIGNING_IDENTITIES[1]}" ]]; then
    print -u2 'Choose an existing signing identity with SIN_CODE_SIGN_IDENTITY (name or SHA-1 from security find-identity -v -p codesigning).'
    print -u2 'Stable certificate signing lets macOS remember capture permission across rebuilds.'
    print -u2 'For a disposable build only, SIN_CODE_SIGN_IDENTITY=- explicitly opts into ad-hoc signing and repeated permission prompts.'
    exit 1
  fi
  SIGNING_IDENTITY=${SIGNING_IDENTITIES[1]}
fi
if [[ "$SIGNING_IDENTITY" == - ]]; then
  print -u2 'Warning: ad-hoc signing changes app identity when code changes; capture permission may need approval again.'
fi
# The bundle contains one executable and resources, with no nested code.
# No timestamp server or network connection is needed for this local build.
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_TO_SIGN"
codesign --verify --strict "$APP_TO_SIGN"
