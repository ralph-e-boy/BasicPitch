# BasicPitch Swift

A native Swift port of Spotify's [basic-pitch](https://github.com/spotify/basic-pitch) — an audio-to-MIDI converter with pitch bend detection. Runs entirely on-device using CoreML with no Python runtime or external dependencies.

Processes a 4-minute song in ~4 seconds on an M1 Mac (parallel CoreML inference across cores).

## Requirements

- iOS 16+ / macOS 13+
- Xcode 15+
- Swift 5.9+

System frameworks only: AVFoundation, CoreML, Accelerate. The library target has zero third-party dependencies.

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(path: "path/to/BasicPitch")
],
targets: [
    .target(name: "YourApp", dependencies: ["BasicPitch"])
]
```

Or in Xcode: File > Add Package Dependencies > Add Local...

The CoreML model (`nmp.mlpackage`) is bundled as an SPM resource and compiled automatically at build time.

## Library Usage

```swift
import BasicPitch

// Load the bundled model
let bp = try BasicPitch()

// Convert audio to MIDI
let result = try bp.predict(audioURL: audioFileURL)

// Write MIDI file
try result.writeMIDI(to: outputURL)

// Or access note events directly
for note in result.noteEvents {
    print("MIDI \(note.midiPitch): \(note.startTime)s – \(note.endTime)s")
}

// Raw MIDI bytes (e.g. for in-memory playback)
let midiData = result.midiData
```

### Async

```swift
let result = try await bp.predict(audioURL: url)
```

### Options

```swift
var options = BasicPitchOptions()
options.onsetThreshold = 0.3         // Onset sensitivity (0–1), lower = more notes
options.frameThreshold = 0.15        // Frame energy threshold (0–1), lower = more notes
options.minimumNoteLengthMS = 127.7  // Shortest note in ms
options.minimumFrequency = 80.0      // Hz, nil = no limit
options.maximumFrequency = 2000.0    // Hz, nil = no limit
options.includePitchBends = true     // Estimate pitch bends from contours
options.multiplePitchBends = false   // Per-note pitch bends (multi-track MIDI)
options.melodiaTrick = true          // Extract polyphonic notes beyond onsets
options.midiTempo = 120              // BPM for the output MIDI file

// Progress callback (useful for UI)
options.progressHandler = { completed, total in
    print("Window \(completed)/\(total)")
}

let result = try bp.predict(audioURL: url, options: options)
```

### Tuning Thresholds

The two most important parameters are `onsetThreshold` and `frameThreshold`. They control the sensitivity/accuracy tradeoff:

| Scenario | `onsetThreshold` | `frameThreshold` | Notes |
|----------|-------------------|-------------------|-------|
| **Default** | 0.3 | 0.15 | Good all-round. Catches most notes including softer high-pitched ones. |
| **Clean solo/duo** | 0.2 | 0.1 | Aggressive — use when the audio is a single instrument or voice with little background noise. |
| **Dense mix** | 0.5 | 0.3 | Conservative — use for busy pop/rock tracks to reduce false positives from drums, distortion, etc. |
| **Precision over recall** | 0.6 | 0.4 | Only the most confident detections survive. Good if you'd rather miss notes than have wrong ones. |

**What they do:**

- **`onsetThreshold`** — How strong a note onset must be to start a new note. Lower values detect softer attacks (e.g. high harmonics, fingerpicked strings). Range: 0–1.
- **`frameThreshold`** — How much energy a frame must have for a note to continue sounding. Lower values let notes ring longer and catch quiet sustained tones. Range: 0–1.
- **`melodiaTrick`** — When enabled (default), extracts additional notes that the onset detector missed by scanning for sustained energy. Helps with polyphonic content. Disable for cleaner but sparser output.
- **`minimumNoteLengthMS`** — Filters out very short detected notes (default 127.7ms). Lower it for fast passages, raise it to reduce noise.
- **`minimumFrequency` / `maximumFrequency`** — Hard frequency cutoffs in Hz. Useful if you know the instrument's range (e.g. `minimumFrequency: 82` for guitar low E, `maximumFrequency: 1200` to ignore high harmonics).

### Custom Model

```swift
// Load a custom .mlmodelc or .mlpackage
let bp = try BasicPitch(modelURL: myModelURL)

// Or pass an MLModelConfiguration for compute unit control
let config = MLModelConfiguration()
config.computeUnits = .cpuOnly
let bp = try BasicPitch(configuration: config)
```

## CLI

A command-line tool is included for quick conversions:

```
# Build (release, into current directory)
make install

# Convert a file
./basic-pitch-cli song.mp3

# Specify output path
./basic-pitch-cli song.wav -o output.mid

# Remote URL
./basic-pitch-cli https://example.com/audio.mp3

# Sensitive detection (clean recordings, solo instruments)
./basic-pitch-cli song.m4a --onset-threshold 0.2 --frame-threshold 0.1

# Conservative detection (dense mixes, drums)
./basic-pitch-cli song.mp3 --onset-threshold 0.5 --frame-threshold 0.3

# Restrict to guitar range, no pitch bends, custom tempo
./basic-pitch-cli song.wav --min-freq 82 --max-freq 1200 --no-pitch-bends --tempo 140

# Skip overwrite prompt
./basic-pitch-cli song.wav --yes
```

Run `./basic-pitch-cli --help` for all options.

### Makefile

```
make build     # Release build
make install   # Build + copy binary to current directory
make test      # Run test suite
make clean     # Remove build artifacts
```

## Supported Audio Formats

Any format AVFoundation can decode: **WAV, MP3, M4A/AAC, AIFF, CAF, FLAC, MP4 audio**. Input is automatically resampled to 22050 Hz mono.

## How It Works

The pipeline mirrors the Python implementation:

1. **Load audio** — AVFoundation decodes and resamples to 22050 Hz mono
2. **Window** — Overlapping 2-second windows (43844 samples, hop 36164)
3. **Infer** — CoreML model predicts note/onset/contour activations per window (run in parallel across cores)
4. **Stitch** — Remove overlap frames, concatenate into continuous matrices
5. **Detect notes** — Onset peak detection, energy tracking, melodia trick for polyphony
6. **Pitch bends** — Gaussian-windowed contour analysis for sub-semitone precision
7. **Write MIDI** — Standard MIDI File with note events, velocities, and pitch bends

### CoreML Model

The bundled model (`nmp.mlpackage`) is the ICASSP 2022 model from the upstream project. It takes raw audio samples and outputs three activation matrices:

| Output | Shape | Description |
|--------|-------|-------------|
| Notes | (172, 88) | Note probability per frame, 88 piano keys |
| Onsets | (172, 88) | Onset probability per frame |
| Contours | (172, 264) | Pitch contour at 3 bins/semitone |

### Performance

Inference runs in parallel using `DispatchQueue.concurrentPerform` with multiple `MLModel` copies. The model uses the Neural Engine when available.

| Audio Length | Windows | Time (M1 Mac) |
|-------------|---------|---------------|
| 10 seconds | 6 | ~0.5s |
| 4 minutes | 276 | ~4s |

Post-processing (note detection, pitch bends, MIDI writing) uses Accelerate (`vDSP`, `cblas`) throughout and adds negligible overhead.

## Architecture

```
Sources/BasicPitch/
├── BasicPitch.swift         Public API — predict(audioURL:options:)
├── BasicPitchError.swift    Error types
├── AudioLoader.swift        AVAudioFile + AVAudioConverter → [Float]
├── AudioWindower.swift      Pad + sliding window with overlap
├── CoreMLInference.swift    MLModel loading, prediction, parallel batch
├── OutputStitcher.swift     Overlap removal + concatenation
├── NoteCreation.swift       Onset detection, note tracking, melodia trick
├── PitchBend.swift          Contour analysis → MIDI pitch bends
├── MIDIWriter.swift         Standard MIDI File format writer
├── Constants.swift          Audio/model constants (sample rate, FFT hop, etc.)
└── Matrix.swift             Row-major 2D array with vDSP operations
```

## License

Apache 2.0, matching the [upstream basic-pitch project](https://github.com/spotify/basic-pitch).

Original model and algorithm by Spotify's Audio Intelligence Lab. See [the paper](https://arxiv.org/abs/2203.09893) (ICASSP 2022).
