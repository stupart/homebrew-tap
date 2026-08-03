class Conch < Formula
  desc "Voice loop for Claude Code: hear your sessions speak, talk your prompts back"
  homepage "https://github.com/stupart/conch"
  version "0.2.0"
  license "MIT"

  depends_on "sox"          # microphone capture
  depends_on "tmux"         # daemon hosting + prompt injection
  depends_on "whisper-cpp"  # local speech-to-text (whisper-cli)
  depends_on :macos

  on_arm do
    url "https://github.com/stupart/conch/releases/download/v0.2.0/conch-macos-arm64.tar.gz"
    sha256 "f4bcfc088ff3023d1ccb52f4b532ad58cf512508bf7f44a19123704f2b8642a2"
  end

  on_intel do
    url "https://github.com/stupart/conch/releases/download/v0.2.0/conch-macos-x64.tar.gz"
    sha256 "2a02205f1427e1a7313be2bbd0a246ad4b9a59dc8820cc5ae478dfa227b04711"
  end

  def install
    bin.install "conch"
  end

  def caveats
    <<~EOS
      One more step — this installs everything (models, hooks, the background
      service, and the Claude Code / Codex plugins):
        conch setup

      Then type /hooks in any Claude Code session you already have open, and
      finish a turn. macOS will ask for microphone access the first time
      something speaks — allow it. If it is ever quiet, run:
        conch doctor

      Natural per-session voices are optional (falls back to the macOS `say` voice):
        uv tool install --with "misaki[en]" "mlx-audio[server]"

      To remove conch and everything it wired up:
        conch uninstall
    EOS
  end

  test do
    assert_match "voice loop for Claude Code", shell_output("#{bin}/conch --help")
    assert_match version.to_s, shell_output("#{bin}/conch version")
  end
end
