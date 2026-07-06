# WhisperFlow

A private, fully local push-to-talk dictation app for macOS. Hold a key, speak, release — cleaned-up text appears at your cursor. No audio, no text, and no screenshots ever leave your Mac.

Built as a local alternative to cloud dictation tools (like Wispr Flow), which send your voice to remote servers for transcription and formatting.

## How it works

Hold **right ⌥ (Option)** → speak → release:

1. **[Parakeet-TDT v3](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)** (via [FluidAudio](https://github.com/FluidInference/FluidAudio)) transcribes your speech on-device, using Apple's Neural Engine. Supports 25 European languages with automatic language detection.
2. A local LLM via **[Ollama](https://ollama.com)** (default: `qwen3:4b`) cleans up the transcript — removes filler words, fixes grammar, keeps your language (never translates).
3. Text is inserted at your cursor via simulated paste, with an Accessibility-API fallback.

If the cleanup step is slow or unavailable, the raw transcript is inserted instead — you always get *something*, never nothing.

**Double-tap right ⌥** (two short taps within half a second) re-inserts the last transcription — handy if your cursor wasn't where you expected and the text landed somewhere unseen.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon
- [Ollama](https://ollama.com) — `brew install ollama`
- Swift 6 toolchain (ships with Xcode / Xcode Command Line Tools)

## Setup

```bash
git clone https://github.com/PtrX/whisper-flow.git
cd whisper-flow

./scripts/setup_ollama.sh          # installs/starts Ollama, pulls qwen3:4b
./scripts/build_app_bundle.sh      # builds and ad-hoc signs WhisperFlow.app

mv WhisperFlow.app /Applications/
open /Applications/WhisperFlow.app
```

On first launch, grant **Microphone** and **Accessibility** access when prompted (Accessibility is required to detect the hotkey and to simulate paste — see [`Info.plist`](Resources/Info.plist)). The Parakeet model (~600 MB) downloads on first use and is cached under `~/Library/Application Support/FluidAudio/`.

WhisperFlow is a menu-bar-only app (no Dock icon) — look for the mic icon in your menu bar.

## Development

```bash
swift build
swift test
```

The core logic (`WhisperFlowCore`) is protocol-based and fully unit-tested with fakes — no mic, model, or network access needed to run the test suite. AppKit/CoreGraphics glue (`WhisperFlowApp`: hotkey event tap, menu bar, app delegate) isn't unit-testable and is verified manually.

Rebuilding regenerates an ad-hoc code signature each time, which may require re-granting Accessibility/Microphone access in System Settings — this is expected, not a bug.

To edit the app icon, change [`Resources/AppIcon.svg`](Resources/AppIcon.svg) and run `./scripts/build_icon.sh`.

## Architecture

| Component | Responsibility |
|---|---|
| `HotkeyListener` | CGEvent tap on right ⌥ (`.flagsChanged`, since a bare modifier press never fires `.keyDown`/`.keyUp`); detects push-to-talk and double-tap |
| `AudioRecorder` | 16kHz mono capture via AVAudioEngine |
| `TranscriptionEngine` / `ParakeetEngine` | Protocol + FluidAudio-backed multilingual ASR |
| `CleanupService` / `OllamaCleanupService` | Local LLM cleanup over Ollama's HTTP API, with timeout |
| `TextInserter` | Cmd+V paste (primary — reliable across native and Electron/Chromium apps), AX API (fallback) |
| `PipelineCoordinator` | Orchestrates the above; encodes the "raw text over no text" fallback rules |
| `MenuBarController` | Menu bar icon + status |

Design rationale and the full implementation plan live under [`docs/superpowers/`](docs/superpowers/).

## Known limitations

- Ad-hoc code signing means Accessibility/Microphone grants don't survive a rebuild (no paid Apple Developer certificate is used).
- First launch downloads the ASR model (~600 MB); needs a network connection once.
- Cleanup quality/latency depends entirely on which local model you point Ollama at — `qwen3:4b` is a reasonable default balance of speed and quality on Apple Silicon.

## License

[MIT](LICENSE)
