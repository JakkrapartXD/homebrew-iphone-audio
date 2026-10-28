# iPhone Audio

Listen to iPhone USB audio through your Mac while keeping Mac audio playing. This is an early Thai-language prototype, tested with Instagram Reels on one Apple Silicon Mac.

## Requirements

- Apple Silicon Mac, macOS 14 or newer. Intel builds are not provided.
- iPhone connected with a data-capable USB cable, unlocked and trusted.
- Accessibility permission for automatically pressing Enable in Audio MIDI Setup.
- Microphone permission for receiving the iPhone audio input. The app does not save recordings.

## Install

After the GitHub release and tap are published:

```sh
brew tap JakkrapartXD/iphone-audio
brew install --cask JakkrapartXD/iphone-audio/iphone-audio
```

If your Homebrew version requires tap trust, review the cask and use `brew trust --cask JakkrapartXD/iphone-audio/iphone-audio` before installing.

The prototype is ad-hoc signed, not Apple Developer ID signed or notarized. macOS may block a downloaded copy. Review the source and use macOS Privacy & Security's Open Anyway flow only if you trust this build. No quarantine removal or Gatekeeper disabling is performed by the installer.

## Use

1. Open iPhone Audio and connect your phone.
2. Grant Accessibility to the installed copy for automatic Enable, or enable the phone manually in Audio MIDI Setup.
3. Click เชื่อมต่อและเริ่มฟัง and allow audio access when prompted.
4. Play audio on your iPhone. Adjust volume or mute inside this app.
5. Stop QuickTime audio monitoring to avoid hearing two copies.

After reconnecting the cable, click Connect again. Automatic reconnection is not implemented. Audio uses the Mac's default output. Phone calls and protected media are not guaranteed to work.

Automatic Enable depends on Audio MIDI Setup's accessibility structure and currently recognizes the English iOS Device/Enable labels (plus Thai Enable labels). macOS changes or other UI languages may require manual Enable. Multiple connected iOS devices are intentionally rejected.

## Build

With Xcode or compatible Swift command line tools installed:

```sh
zsh build.sh
open "build/iPhone Audio.app"
```

The build script produces an ARM64 application and verifies its ad-hoc signature. Rebuilding may require removing and re-adding its Accessibility entry because the signature changes.

`Sources/main.swift` contains the SwiftUI interface, Accessibility activation and AVFoundation audio preview. `Info.plist` supplies the microphone usage explanation. No third-party dependencies are required.
