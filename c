# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
make build          # Release build (both CLIs) + Metal shader library
make install        # Build + copy binaries (basic-pitch-cli, basic-pitch-demucs-cli, mlx.metallib) to repo root
make test           # Run all tests (swift test)
make clean          # Remove build artifacts

swift build -c release --disable-sandbox   # Build without Metal shaders
swift test --filter BasicPitchTests.MatrixTests   # Run a single test class
swift test --filter BasicPitchTests.MatrixTests/testAdd   # Run a single test method
```

The Metal shader build (`scripts/build_mlx_metallib.sh`) requires the Metal Toolchain — install with `xcodebuild -downloadComponent MetalToolchain` if missing.

## Architecture

Swift port of Spotify's basic-pitch (audio-to-MIDI). Four SPM targets:

- **BasicPitch** — Core library. Zero third-party dependencies. Uses AVFoundation, CoreML, Accelerate.
- **BasicPitchDemucs** — Adds Demucs stem separation (depends on `demucs-mlx-swift`). Separates audio into stems then transcribes each independently.
- **BasicPitchCLI** / **BasicPitchDemucsCLI** — ArgumentParser CLIs wrapping the above.

### Processing Pipeline (BasicPitch library)

`AudioLoader` → `AudioWindower` → `CoreMLInference` → `OutputStitcher` → `NoteCreation` → `PitchBend` → `MIDIWriter`

1. **AudioLoader** — Decode + resample to 22050 Hz mono via AVFoundation
2. **AudioWindower** — Overlapping 2-second windows (43844 samples, hop 36164)
3. **CoreMLInference** — Parallel CoreML prediction using multiple `MLModel` copies via `DispatchQueue.concurrentPerform`
4. **OutputStitcher** — Remove overlap frames, concatenate into continuous matrices
5. **NoteCreation** — Onset peak detection, energy tracking, melodia trick for polyphony
6. **PitchBend** — Gaussian-windowed contour analysis for sub-semitone pitch bends
7. **MIDIWriter** — Standard MIDI File format writer (raw byte construction)

**Matrix.swift** — Row-major 2D array backing type used throughout, with vDSP/cblas operations.

**StemTranscriber** — Orchestrates Demucs separation then runs BasicPitch on each stem, assigning GM MIDI channels/programs per stem type.

### CoreML Model

Bundled at `Sources/BasicPitch/Resources/nmp.mlpackage`. Input: raw audio samples. Outputs: Notes (172×88), Onsets (172×88), Contours (172×264).

## Code Style

- Swift 5.9+, platforms: iOS 17+ / macOS 14+
- Heavy use of Accelerate framework (`vDSP`, `cblas`) for numerical operations
- Parallel inference via GCD (`DispatchQueue.concurrentPerform`)
- Public API entry point: `BasicPitch.predict(audioURL:options:)`
