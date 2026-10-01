# macOS-Diktier-App

- Native macOS app (Swift/AppKit/SwiftUI), targeting Apple Silicon and 16 GB RAM; automatic German/English recognition is the default.
- Verify with `swift test -j 4`, `scripts/build.sh`, then `scripts/verify.sh`; save long command output to logs.
- `Engine/` owns the isolated Qwen MLX executable; `Sources/FlowCore/` owns audio validation, transcription, model integrity and history.
- SwiftPM app entry points using `@main` must not be named `main.swift` (here `Sources/DiktierApp/DiktierApp.swift`), when the target has multiple files (`swift test -j 4`).
- Formerly "Whisper Flow": keep bundle ID `de.local.whisperflow`, the UserDefaults keys and `~/Library/Application Support/WhisperFlow/` unchanged so existing settings, models and history keep working.
- Do not commit downloaded models, build outputs, recordings or transcripts.
- `scripts/build.sh` must map source paths with `-ffile-prefix-map`/`-file-prefix-map` and strip debug data before signing; stripping alone leaves this machine's paths in the engines' C++ assertion strings (`rg -a -l '/Users/' dist/*.app`).
- SwiftPM regenerates resource accessors containing literal build paths on every planning pass; `scripts/portable_resources.py` rewrites them and replays the resource-module compiler and engine linker commands from `Engine/.build/release.yaml` without another SwiftPM planning pass.
- `Sources/DiktierApp/HALMicrophone.swift` captures at the selected device's native rate after `AudioUnitInitialize`; switching `AVAudioEngine.inputNode.audioUnit` then installing a tap from its cached output format fails with CoreAudio -10877 (`swift test --filter HardwareRecordingTests`).
- `Sources/FlowCore/QwenWorker.swift` must not call `Process.waitUntilExit()` from the cooperative executor after killing a worker; it can deadlock `swift test -j 4` during cancellation or shutdown.
- `scripts/verify_audio.py` must launch the engine directly; timing wrappers leave their engine child running after `subprocess.run(..., timeout=...)` kills only the wrapper.
- `URLSession.download(from:)` and `download(from:delegate:)` omit intermediate progress on this Mac; use an explicit download task and delegate (`Sources/DiktierApp/ModelManager.swift`, `swift test --filter DownloadProgressTests`).
- SwiftPM does not compile MLX Metal shaders: build the `mlx-metallib` CMake target, place it at `Contents/Resources/default.metallib`, and let `Engine/Sources/flow-qwen/main.swift` set its working directory before MLX initializes; resources in `Contents/MacOS` fail `codesign --verify --deep --strict`.
