class Seashell < Formula
  desc "Local meeting capture, transcription, and searchable transcript library"
  homepage "https://github.com/stupart/seashell"
  url "https://github.com/stupart/seashell/archive/924c9373f168431cdd33bcb67f52089875ad53c2.tar.gz"
  version "1.1.0-rc1"
  sha256 "1b06fb41a20805f3c1655becb550fb3a5b67695ef86a15ef249c3d88c2ad2422"
  # Upstream has not selected a license yet; do not invent one in the tap.

  depends_on "cmake" => :build
  depends_on "ffmpeg"
  depends_on macos: :sonoma
  depends_on "oven-sh/bun/bun"
  depends_on "sox"

  resource "whisper-source" do
    url "https://github.com/ggml-org/whisper.cpp/archive/927cfce34f31707e17f2bff35c349632fb9e2c3a.tar.gz"
    sha256 "41b664fee09e79176ac277b5237debec34f8d74af3c7d71f333f1ec67989ecde"
  end

  resource "whisper-model" do
    url "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
    sha256 "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
  end

  resource "vad-model" do
    url "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin"
    sha256 "2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987"
  end

  def install
    resource("whisper-source").stage(buildpath/"whisper.cpp")
    system "cmake", "-S", "whisper.cpp", "-B", "whisper.cpp/build", *std_cmake_args,
           "-DBUILD_SHARED_LIBS=OFF", "-DGGML_NATIVE=OFF", "-DGGML_METAL=ON",
           "-DGGML_METAL_EMBED_LIBRARY=ON"
    system "cmake", "--build", "whisper.cpp/build", "--parallel", ENV.make_jobs,
           "--target", "whisper-cli", "whisper-server"
    system "bash", "scripts/build-native.sh"
    ENV["BUN_INSTALL_CACHE_DIR"] = buildpath/"bun-cache"
    system formula_opt_bin("oven-sh/bun/bun")/"bun", "install", "--frozen-lockfile", "--production"

    libexec.install "src", "scripts", "seashell", "package.json", "bun.lock", "node_modules"
    (libexec/"native").install "native/bin"
    (libexec/"whisper.cpp/build/bin").install "whisper.cpp/build/bin/whisper-cli",
                                            "whisper.cpp/build/bin/whisper-server"
    resource("whisper-model").stage do
      (libexec/"models").install "ggml-large-v3-turbo-q5_0.bin"
    end
    resource("vad-model").stage do
      (libexec/"whisper.cpp/models").install "ggml-silero-v6.2.0.bin"
    end

    runtime_path = %w[oven-sh/bun/bun ffmpeg sox].map { |name| formula_opt_bin(name) }.join(":")
    (bin/"seashell").write_env_script libexec/"seashell",
      PATH:                  "#{runtime_path}:$PATH",
      SEASHELL_MANAGED_BY:   "homebrew",
      SEASHELL_PACKAGE_ROOT: opt_libexec
  end

  def caveats
    <<~EOS
      Open the app with:
        seashell

      Local models are included. No API key or separate setup is required.
      macOS will ask for microphone/system-audio permission when first used.
      To opt into the background meeting watcher at login:
        seashell setup

      Update this installation with:
        brew update && brew upgrade stupart/tap/seashell

      This is the tested 1.1.0 release candidate, pinned to its reviewed source.
      Speaker diarization and Humain meeting intelligence are optional additions.
    EOS
  end

  test do
    ENV["SEASHELL_CONFIG"] = testpath/"config.json"
    ENV["SEASHELL_LIBRARY_DIR"] = testpath/"library"
    assert_match "Sea Shell", shell_output("#{bin}/seashell --help")
    manifest = JSON.parse(shell_output("#{bin}/seashell capabilities --json"))
    assert_equal "product.seashell", manifest.fetch("product").fetch("id")
    system bin/"seashell", "setup", "--no-autostart"
    config = (testpath/"config.json").read
    system bin/"seashell", "setup", "--no-autostart"
    assert_equal config, (testpath/"config.json").read
    assert JSON.parse(shell_output("#{bin}/seashell doctor --json")).fetch("ok")

    speech = "The project meeting is on Tuesday. Alice will prepare the release notes. " \
             "Bob will test the audio recorder."
    system "/usr/bin/say", "-o", testpath/"speech.aiff", speech
    record = JSON.parse(shell_output("#{bin}/seashell transcribe #{testpath}/speech.aiff --format json --quiet"))
    text = record.fetch("transcript").map { |segment| segment.fetch("text") }.join(" ").downcase
    %w[tuesday alice release bob audio].each { |word| assert_includes text, word }
    assert_match "brew upgrade stupart/tap/seashell", shell_output("#{bin}/seashell update 2>&1", 1)
  end
end
