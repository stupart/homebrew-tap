class Conch < Formula
  desc "Voice loop for Claude Code: hear your sessions speak, talk your prompts back"
  homepage "https://github.com/stupart/conch"
  version "0.1.0"
  license "MIT"

  depends_on "sox"          # microphone capture
  depends_on "tmux"         # daemon hosting + prompt injection
  depends_on "whisper-cpp"  # local speech-to-text (whisper-cli)
  depends_on :macos

  on_arm do
    url "https://github.com/stupart/conch/releases/download/v0.1.0/conch-macos-arm64.tar.gz"
    sha256 "3c9ac58e2944863ac82e7d881e6af87b68e4a5db1d610461b416a844e7e1a2f9"
  end

  on_intel do
    url "https://github.com/stupart/conch/releases/download/v0.1.0/conch-macos-x64.tar.gz"
    sha256 "c046e51177596c6c0b42d88d09a6de7b912128815a417df939f682b11df658d9"
  end

  def install
    bin.install "conch"
  end

  def caveats
    <<~EOS
      One more step — download the speech models and wire the Claude Code hooks:
        conch setup

      Then run it as a background service (starts at login, self-heals on crash):
        conch service install

      Natural per-session voices are optional (falls back to the macOS `say` voice):
        uv tool install --with "misaki[en]" "mlx-audio[server]"
    EOS
  end

  test do
    assert_match "voice loop for Claude Code", shell_output("#{bin}/conch 2>&1")
  end
end
