#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="${1:-$PWD/build/iPhone Audio.app}"
mkdir -p "$app/Contents/MacOS" "$PWD/build/module-cache"
mkdir -p "$app/Contents/Resources" "$PWD/build/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$PWD/build/module-cache" Sources/main.swift -o "$app/Contents/MacOS/iPhoneAudio"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier local.dandelion.iphone-audio-spike "$app"
codesign --verify --strict "$app"
printf 'Built: %s\n' "$app"
