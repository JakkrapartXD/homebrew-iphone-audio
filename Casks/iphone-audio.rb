cask "iphone-audio" do
  version "0.1.3"
  sha256 "ab567e9cda841baf821cf44418dbd62b24503cb966593fb2d4685e8615cb349c"

  url "https://github.com/JakkrapartXD/homebrew-iphone-audio/releases/download/v#{version}/iPhone-Audio-#{version}-arm64.zip"
  name "iPhone Audio"
  desc "Listen to iPhone USB audio through your Mac"
  homepage "https://github.com/JakkrapartXD/homebrew-iphone-audio"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "iPhone Audio.app"

  caveats <<~EOS
    Prototype: ad-hoc signed and not notarized by Apple.
    Accessibility permission is needed for automatic Enable in Audio MIDI Setup.
    Microphone permission is needed to receive iPhone USB audio.
    After reconnecting the USB cable, click Connect again.
  EOS
end
