class Conch < Formula
  desc "Voice loop for Claude Code: hear your sessions speak, talk your prompts back"
  homepage "https://github.com/stupart/conch"
  version "0.2.1"
  license "MIT"

  depends_on "sox"          # microphone capture
  depends_on "tmux"         # daemon hosting + prompt injection
  depends_on "whisper-cpp"  # local speech-to-text (whisper-cli)
  depends_on :macos

  on_arm do
    url "https://github.com/stupart/conch/releases/download/v0.2.1/conch-macos-arm64.tar.gz"
    sha256 "0a07fd254508a8d0a9fa8b00d6ff5f458a06339ac91ba54bfc135b95d3c12a9a"
  end

  on_intel do
    url "https://github.com/stupart/conch/releases/download/v0.2.1/conch-macos-x64.tar.gz"
    sha256 "27db70caca847d985b13a79fdbdeb91547b3cc2a7e2d2d12001e30d6af8a6ef6"
  end

  def install
    bin.install "conch"
    # The app ships in the formula rather than a cask on purpose: Homebrew
    # quarantines cask artifacts, and a quarantined app that is signed but not
    # notarized is refused by Gatekeeper. A formula-installed bundle is not
    # quarantined, so one `brew install` delivers a working CLI and app.
    prefix.install "conch.app" if File.exist?("conch.app")
  end

  def post_install
    app = prefix/"conch.app"
    return unless app.exist?

    link = Pathname.new("/Applications/conch.app")
    # Only ever replace a link we own — never a user's real app bundle.
    link.unlink if link.symlink?
    link.make_symlink(app) unless link.exist?
  rescue StandardError
    # /Applications may be unwritable; the app still lives in the prefix.
    nil
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

      conch.app is linked into /Applications — it shows every session, renders
      finished work inline, and lets you talk back. The terminal dashboard
      (`conch`) is still there for ssh.

      To remove conch and everything it wired up:
        conch uninstall
    EOS
  end

  test do
    assert_match "voice loop for Claude Code", shell_output("#{bin}/conch --help")
    assert_match version.to_s, shell_output("#{bin}/conch version")
  end
end
