class Seashell < Formula
  desc "Local meeting capture, transcription, and searchable transcript library"
  homepage "https://github.com/stupart/seashell"
  url "https://github.com/stupart/seashell/archive/bfdb1cffb9b2835a6833475cd5cb0eff82eaf223.tar.gz"
  version "1.1.0-rc22"
  sha256 "9449331ae19bdce4c3df115012eb6c6116b2a47fe64901a8ec1a540208975c25"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "ffmpeg"
  depends_on macos: :sonoma
  depends_on "node"
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

  resource "whisper-model-license" do
    url "https://raw.githubusercontent.com/openai/whisper/86098128c0b4f24f0e2aa2994de830614b474227/LICENSE"
    sha256 "b5d65a59060e68c4ff940e1eddfa6f94b2d68fdf58ed7f4dd57721c997e35e9d"
  end

  resource "vad-model-license" do
    url "https://raw.githubusercontent.com/snakers4/silero-vad/be95df9152c0d7618fa1edfeb296fc3dae32376f/LICENSE"
    sha256 "2e63e9a38b6e8fc0c7bc37ce174caca1862870856c6daf5697cfb785e925520b"
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
    (pkgshare/"licenses/seashell").install "LICENSE"
    # Homebrew's SOURCE_DATE_EPOCH disables ggml's default Intel SIMD flags.
    # Match the Haswell baseline already required by the bundled x64 Bun.
    cpu_args = if Hardware::CPU.intel?
      %w[SSE42 AVX AVX2 BMI2 FMA F16C].map { |feature| "-DGGML_#{feature}=ON" }
    else
      []
    end
    # Upstream Homebrew ggml also limits Metal to Apple Silicon.
    metal = Hardware::CPU.arm? ? "ON" : "OFF"
    resource("bun-runtime").stage do
      (libexec/"runtime/bin").install "bun"
    end
    resource("bun-license").stage do
      (pkgshare/"licenses/bun").install "LICENSE.md"
    end
    resource("whisper-source").stage(buildpath/"whisper.cpp")
    (pkgshare/"licenses/whisper.cpp").install "whisper.cpp/LICENSE"
    resource("whisper-model-license").stage do
      (pkgshare/"licenses/whisper-model").install "LICENSE"
    end
    resource("vad-model-license").stage do
      (pkgshare/"licenses/silero-vad").install "LICENSE"
    end
    system "cmake", "-S", "whisper.cpp", "-B", "whisper.cpp/build", *std_cmake_args,
           "-DBUILD_SHARED_LIBS=OFF", "-DGGML_NATIVE=OFF", "-DGGML_METAL=#{metal}",
           "-DGGML_METAL_EMBED_LIBRARY=ON", *cpu_args
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

    runtime_path = [opt_libexec/"runtime/bin", *%w[ffmpeg sox node].map { |name| formula_opt_bin(name) }].join(":")
    (bin/"seashell").write_env_script libexec/"seashell",
      PATH:                  "#{runtime_path}:$PATH",
      SEASHELL_MANAGED_BY:   "homebrew",
      SEASHELL_PACKAGE_ROOT: opt_libexec
  end

  def caveats
    <<~EOS
      Open the app with:
        seashell
      Press , in the app (or run `seashell status`) to see what works and fix the rest.

      Local models are included. No API key or separate setup is required.
      Background meetings record your microphone through "Seashell Microphone".
      Allow it once (macOS asks; choose Allow):
        seashell meeting microphone setup
      Optional: name meetings after their calendar event (Seashell Calendar):
        seashell meeting calendar setup
      To opt into the background meeting watcher at login:
        seashell setup

      Update this installation with:
        brew update && brew upgrade stupart/tap/seashell

      This is the tested 1.1.0 release candidate, pinned to its reviewed source.
      Speaker diarization and Humain meeting intelligence are optional additions.
      Press V for experimental Google Meet speaker names in Chrome.
      Set up macOS Accessibility for this window and background meetings:
        seashell meeting speakers setup
      Allow the entries macOS shows, then verify both permission scopes:
        seashell meeting speakers check
      Terminal permission alone does not enable background meeting detection.
      From rc22 the background watcher restarts itself after upgrades.
      Upgrading from an older watcher? Finish recording, then run:
        seashell meeting autostart enable
        seashell meeting speakers setup
      Meetings split into pieces by older versions can be joined:
        seashell meeting merge --auto --dry-run
      The permanent permission host is named Seashell Background.
      Background meetings now show live text and microphone/computer audio health.
      No browser extension or developer setting is required.
      While your Meet mic is unmuted, keep its People/Participants panel open.
      Safari speaker names are not yet verified.
      For optional local voice separation, run:
        seashell setup --speakers --login
      Install a trusted private Humain package with:
        seashell ai install /path/to/humain-engine-0.0.1.tgz
      Choose meeting AI interactively (or press P in the app):
        seashell ai setup
    EOS
  end

  test do
    # Exercise the wrapper without any preinstalled Bun or Homebrew PATH.
    ENV["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    ENV["SEASHELL_CONFIG"] = testpath/"config.json"
    ENV["SEASHELL_HUMAIN_DIR"] = testpath/"intelligence"
    ENV["HUMAIN_CLI"] = ""
    ENV["SEASHELL_DIARIZATION_HOME"] = testpath/"speakers"
    ENV["HF_HOME"] = testpath/"huggingface"
    ENV.delete("SEASHELL_DIARIZATION_PYTHON")
    ENV.delete("SEASHELL_PYTHON")
    ENV["SEASHELL_LIBRARY_DIR"] = testpath/"library"
    assert_match "Sea Shell", shell_output("#{bin}/seashell --help")
    assert_match "seashell ai setup", shell_output("#{bin}/seashell --help")
    assert_match "meeting speakers setup", shell_output("#{bin}/seashell --help")
    meet = JSON.parse(shell_output("#{bin}/seashell meeting speakers check --json"))
    assert_equal "off", meet.fetch("state")

    # Replay sanitized AX evidence without opening a browser or asking for permission.
    accessibility_helper = libexec/"native/bin/seashell-meeting-accessibility"
    assert_predicate accessibility_helper, :executable?
    # Background microphone capture needs the self-responsible native recorder.
    assert_predicate libexec/"native/bin/seashell-microphone", :executable?
    assert_predicate libexec/"native/bin/seashell-calendar", :executable?
    assert_match "No split meetings found.", shell_output("#{bin}/seashell meeting merge --auto --dry-run")
    (testpath/"meet-accessibility.json").write <<~JSON
      {
        "browsers": [{
          "browser": "chrome",
          "running": true,
          "root": {"role": "AXApplication", "children": [{
            "role": "AXWindow", "children": [{
              "role": "AXWebArea",
              "url": "https://meet.google.com/abc-defg-hij",
              "children": [
                {"role": "AXButton", "description": "Leave call"},
                {"role": "AXButton", "description": "Turn on microphone"}
              ]
            }]
          }]}
        }]
      }
    JSON
    evidence = JSON.parse(shell_output("#{accessibility_helper} --fixture #{testpath}/meet-accessibility.json"))
    assert_equal "accessibility", evidence.fetch("transport")
    assert_equal "connected", evidence.fetch("state")
    assert_equal "chrome", evidence.fetch("browser")
    assert_equal true, evidence.fetch("snapshot").fetch("joined")
    assert_equal "/abc-defg-hij", evidence.fetch("snapshot").fetch("meeting")
    assert_empty evidence.fetch("snapshot").fetch("participants")
    refute evidence.key?("accessibilityTrusted")

    # An unreadable other browser must not erase a positively joined call.
    partial_fixture = JSON.parse((testpath/"meet-accessibility.json").read)
    partial_fixture.fetch("browsers") << { "browser" => "safari", "running" => true }
    (testpath/"meet-partial.json").write JSON.generate(partial_fixture)
    partial = JSON.parse(shell_output("#{accessibility_helper} --fixture #{testpath}/meet-partial.json"))
    assert_equal "unavailable", partial.fetch("state")
    assert_equal "chrome", partial.fetch("browser")
    assert_equal true, partial.fetch("snapshot").fetch("joined")
    assert_empty partial.fetch("snapshot").fetch("participants")
    refute partial["absenceConfirmed"]

    intelligence = JSON.parse(shell_output("#{bin}/seashell ai status --json", 1))
    assert_equal false, intelligence.fetch("ready")
    assert_includes intelligence.fetch("help"), "seashell ai install"
    manifest = JSON.parse(shell_output("#{bin}/seashell capabilities --json"))
    assert_equal "product.seashell", manifest.fetch("product").fetch("id")
    speakers = manifest.fetch("capabilities").first.fetch("optionalFeatures").find do |feature|
      feature.fetch("id") == "speaker-diarization"
    end
    assert_equal false, speakers.fetch("ready")
    assert_includes speakers.fetch("nextStep"), "seashell setup --speakers"
    system bin/"seashell", "setup", "--no-autostart"
    config = (testpath/"config.json").read
    system bin/"seashell", "setup", "--no-autostart"
    assert_equal config, (testpath/"config.json").read
    assert JSON.parse(shell_output("#{bin}/seashell doctor --json")).fetch("ok")

    # macOS say can return empty audio in a clean, headless test account.
    # This fixture is part of the checksum-pinned Whisper source archive.
    # Lead-in silence catches VAD-compressed token timestamps without another ASR run.
    system formula_opt_bin("ffmpeg")/"ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
           "-i", pkgshare/"jfk.wav", "-af", "adelay=4000:all=1", "-c:a", "pcm_s16le", testpath/"speech.wav"
    duration_probe = "#{formula_opt_bin("ffmpeg")}/ffprobe -v error -show_entries format=duration -of json"
    duration_data = JSON.parse(shell_output("#{duration_probe} #{testpath}/speech.wav"))
    duration = duration_data.fetch("format").fetch("duration").to_f
    record = JSON.parse(shell_output("#{bin}/seashell transcribe #{testpath}/speech.wav --format json --quiet"))
    segments = record.fetch("transcript")
    text = segments.map { |segment| segment.fetch("text") }.join(" ").downcase
    assert_includes text, "ask not what your country"
    assert_includes text, "what you can do for your country"
    assert_operator segments.first.fetch("start"), :>=, 3.0
    assert_in_delta duration, segments.last.fetch("end"), 2.0,
                    "The final words must stay on the original audio timeline after leading silence"
    # Exercise the installed background draft worker with committed fixture audio.
    # No microphone, browser, permissions, generated voice or cloud account needed.
    (testpath/"live-draft-smoke.ts").write <<~JS
      import assert from 'node:assert/strict';
      import { readFileSync } from 'node:fs';
      import { basename } from 'node:path';
      import { CaptureSessionStore } from '#{libexec}/src/capture-session.ts';
      import { startBackgroundLiveTranscript } from '#{libexec}/src/background-live-transcript.ts';
      import { createTranscriptRecord } from '#{libexec}/src/transcript-record.ts';
      import { findTranscriptRecord, saveTranscriptRecord } from '#{libexec}/src/transcript-library.ts';
      import { meetingRuntimeHostPath } from '#{libexec}/src/runtime-host.ts';
      assert.equal(basename(meetingRuntimeHostPath()), 'Seashell Background');
      const library = '#{testpath}/live-library';
      const record = createTranscriptRecord({ transcript: [], speakers: [] }, { id: 'package-live-smoke' });
      saveTranscriptRecord(library, record);
      const store = new CaptureSessionStore({ libraryDir: library, sessionId: record.id, startedAtUnixMs: Date.now() });
      const chunk = await store.commitChunkAsync({ sourcePath: '#{testpath}/speech.wav', trackId: 'microphone',
        startSeconds: 0, endSeconds: #{duration}, audible: true });
      const original = readFileSync(chunk.path);
      const worker = startBackgroundLiveTranscript({ libraryDir: library, record, publishIntervalMs: 100 });
      try {
        worker.enqueue(chunk);
        const deadline = Date.now() + 45000;
        while (!findTranscriptRecord(library, record.id).record.transcript.length && Date.now() < deadline) {
          if (worker.status.stage === 'delayed') throw new Error(worker.status.detail);
          await Bun.sleep(50);
        }
        const live = findTranscriptRecord(library, record.id).record;
        const text = live.transcript.map(segment => segment.text).join(' ').toLowerCase();
        assert.ok(text.includes('what you can do for your country'), text);
        assert.notEqual(worker.status.stage, 'stopped');
        assert.deepEqual(readFileSync(chunk.path), original);
        console.log('PASS: installed worker saved live text before close');
      } finally { await worker.close(); }
    JS
    assert_match "PASS: installed worker saved live text before close",
                 shell_output("#{libexec}/runtime/bin/bun #{testpath}/live-draft-smoke.ts")
    assert_match "brew upgrade stupart/tap/seashell", shell_output("#{bin}/seashell update 2>&1", 1)
  end
end
