class Seashell < Formula
  desc "Local meeting capture, transcription, and searchable transcript library"
  homepage "https://github.com/stupart/seashell"
  url "https://github.com/stupart/seashell/archive/53ad140cc1f5e6a1eec554d9e27c0fc6bb25f551.tar.gz"
  version "1.1.0-rc2"
  revision 1
  sha256 "547c1da67d498b610d44b06053604afa625684ce860c4fae2e6a367e0e14d92d"
  # Upstream has not selected a license yet; do not invent one in the tap.

  depends_on "cmake" => :build
  depends_on "ffmpeg"
  depends_on macos: :sonoma
  depends_on "sox"

  # Bundle the runtime privately so a fresh install needs no additional tap.
  resource "bun-runtime" do
    on_arm do
      url "https://github.com/oven-sh/bun/releases/download/bun-v1.4.2/bun-darwin-aarch64.zip"
      sha256 "90987a3a16d7db556d886ac3d551e7b6d3edf0a1cf43acaed622e8676be1d12f"
    end
    on_intel do
      url "https://github.com/oven-sh/bun/releases/download/bun-v1.4.2/bun-darwin-x64.zip"
      sha256 "80520d7e17526308c9185d261679ac6d27798d3803a0e9f7ff9121ab8affb012"
    end
  end

  resource "whisper-source" do
    url "https://github.com/ggml-org/whisper.cpp/archive/927cfce34f31707e17f2bff35c349632fb9e2c3a.tar.gz"
    sha256 "41b664fee09e79176ac277b5237debec34f8d74af3c7d71f333f1ec67989ecde"
  end

  resource "bun-license" do
    url "https://raw.githubusercontent.com/oven-sh/bun/bun-v1.4.2/LICENSE.md"
    sha256 "b9caf52728691b4057e371232c221a132883198be2f3d2ddf92c90404c984b1a"
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
    # This source-only formula builds on the user's Mac. Preserve native CPU
    # flags; disabling them under SOURCE_DATE_EPOCH disables Intel SIMD too.
    # Bottles would need portable CPU variants instead of -march=native.
    ENV.runtime_cpu_detection
    resource("bun-runtime").stage do
      (libexec/"runtime/bin").install "bun"
    end
    resource("bun-license").stage do
      (pkgshare/"licenses/bun").install "LICENSE.md"
    end
    resource("whisper-source").stage(buildpath/"whisper.cpp")
    system "cmake", "-S", "whisper.cpp", "-B", "whisper.cpp/build", *std_cmake_args,
           "-DBUILD_SHARED_LIBS=OFF", "-DGGML_NATIVE=ON", "-DGGML_METAL=ON",
           "-DGGML_METAL_EMBED_LIBRARY=ON"
    system "cmake", "--build", "whisper.cpp/build", "--parallel", ENV.make_jobs,
           "--target", "whisper-cli", "whisper-server"
    system "bash", "scripts/build-native.sh"
    ENV["BUN_INSTALL_CACHE_DIR"] = buildpath/"bun-cache"
    system libexec/"runtime/bin/bun", "install", "--frozen-lockfile", "--production"

    libexec.install "src", "scripts", "seashell", "package.json", "bun.lock", "node_modules"
    (libexec/"native").install "native/bin"
    (libexec/"whisper.cpp/build/bin").install "whisper.cpp/build/bin/whisper-cli",
                                            "whisper.cpp/build/bin/whisper-server"
    pkgshare.install "whisper.cpp/samples/jfk.wav"
    resource("whisper-model").stage do
      (libexec/"models").install "ggml-large-v3-turbo-q5_0.bin"
    end
    resource("vad-model").stage do
      (libexec/"whisper.cpp/models").install "ggml-silero-v6.2.0.bin"
    end

    runtime_path = [opt_libexec/"runtime/bin", *%w[ffmpeg sox].map { |name| formula_opt_bin(name) }].join(":")
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
    # Exercise the wrapper without any preinstalled Bun or Homebrew PATH.
    ENV["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
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

    # macOS say can return empty audio in a clean, headless test account.
    # This fixture is part of the checksum-pinned Whisper source archive.
    cp pkgshare/"jfk.wav", testpath/"speech.wav"
    record = JSON.parse(shell_output("#{bin}/seashell transcribe #{testpath}/speech.wav --format json --quiet"))
    text = record.fetch("transcript").map { |segment| segment.fetch("text") }.join(" ").downcase
    assert_includes text, "ask not what your country"
    assert_includes text, "what you can do for your country"
    assert_match "brew upgrade stupart/tap/seashell", shell_output("#{bin}/seashell update 2>&1", 1)
  end
end
