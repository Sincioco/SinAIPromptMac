#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./build.sh
ditto -c -k --sequesterRsrc --keepParent "build/Sin AI Prompt.app" "build/SinAIPromptMac.zip"
printf 'Package: %s/build/SinAIPromptMac.zip\n' "$PWD"
