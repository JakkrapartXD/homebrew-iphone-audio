#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="$PWD/build/iPhone Audio.app"
mkdir -p "$app/Contents/MacOS" "$PWD/build/module-cache"
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$PWD/build/module-cache" Sources/main.swift -o "$app/Contents/MacOS/iPhoneAudio"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier local.dandelion.iphone-audio-spike "$app"
codesign --verify --strict "$app"
printf 'Built: %s\n' "$app"
