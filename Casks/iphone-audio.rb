cask "iphone-audio" do
  version "0.1.5"
  sha256 "7fa5df365c6d3b2670e4517393e30ece6c53ade9e64fb2eb00eb25fd4ea00acf"

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
