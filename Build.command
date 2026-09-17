#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./build.sh
open "build/Sin AI Prompt.app"
