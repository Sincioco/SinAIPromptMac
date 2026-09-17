#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/Sin AI Prompt.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-nullability-completeness -Wno-deprecated-declarations -mmacosx-version-min=13.3 -ISources Sources/*.m -framework Cocoa -framework WebKit -framework PDFKit -framework UniformTypeIdentifiers -framework ImageIO -framework CoreGraphics -framework QuartzCore -o "$APP/Contents/MacOS/SinAIPrompt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Web "$APP/Contents/Resources/"
cp Resources/AppIcon.png "$APP/Contents/Resources/"
if [[ -f docs/PARITY.md ]]; then cp docs/PARITY.md "$APP/Contents/Resources/"; fi
ICONSET="$PWD/build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size*2))
  sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
./scripts/sign-app.sh "$APP"
printf 'Built: %s\n' "$APP"
