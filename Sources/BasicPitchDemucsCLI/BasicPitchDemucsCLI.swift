import ArgumentParser
import BasicPitch
import BasicPitchDemucs
import Foundation

@main
struct BasicPitchDemucsCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "basic-pitch-demucs-cli",
        abstract: "Convert audio to MIDI with optional Demucs stem separation.",
        discussion: """
            Accepts local audio files. When --split-stems is enabled, first separates the \
            audio into stems (drums, bass, vocals, other) using Demucs, then transcribes \
            each stem to MIDI.

            Examples:
              basic-pitch-demucs-cli song.mp3
              basic-pitch-demucs-cli song.mp3 --split-stems --multi-track -o output.mid
              basic-pitch-demucs-cli song.mp3 --split-stems --stems vocals,bass
            """
    )

    // MARK: - Input/Output

    @Argument(help: "Audio file path.")
    var input: String

    @Option(name: [.short, .customLong("output")], help: "Output MIDI file path. Defaults to <input>.mid.")
    var output: String?

    @Flag(name: .customLong("yes"), help: "Overwrite output without asking.")
    var forceOverwrite = false

    // MARK: - BasicPitch options

    @Option(help: "Onset detection threshold (0-1). Default: 0.4")
    var onsetThreshold: Float = 0.4

    @Option(help: "Frame energy threshold (0-1). Default: 0.25")
    var frameThreshold: Float = 0.25

    @Option(help: "Minimum note length in milliseconds. Default: 127.7")
    var minNoteLength: Float = 127.7

    @Option(help: "Minimum frequency in Hz.")
    var minFreq: Float?

    @Option(help: "Maximum frequency in Hz.")
    var maxFreq: Float?

    @Option(help: "MIDI tempo in BPM. Default: 120")
    var tempo: Float = 120

    @Flag(name: .customLong("no-pitch-bends"), help: "Disable pitch bend estimation.")
    var noPitchBends = false

    @Flag(name: .customLong("multi-pitch-bends"), help: "Independent pitch bends per note (multi-track MIDI).")
    var multiPitchBends = false

    @Flag(name: .customLong("no-melodia"), help: "Disable the melodia post-processing trick.")
    var noMelodia = false

    // MARK: - Demucs options

    @Flag(name: .customLong("split-stems"), help: "Enable Demucs stem separation before transcription.")
    var splitStems = false

    @Option(name: .customLong("stem-model"), help: "Demucs model name. Default: htdemucs")
    var stemModel: String = "htdemucs"

    @Option(name: .customLong("stems"), help: "Comma-separated list of stems to transcribe (e.g. vocals,bass). Default: all.")
    var stemsFilter: String?

    @Flag(name: .customLong("multi-track"), help: "Output a single multi-track MIDI instead of separate files per stem.")
    var multiTrack = false

    // MARK: - Run

    mutating func run() throws {
        let audioURL = resolveInputURL()
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ValidationError("File not found: \(audioURL.path)")
        }

        let bpOptions = makeBasicPitchOptions()

        if splitStems {
            try runWithStems(audioURL: audioURL, bpOptions: bpOptions)
        } else {
            try runDirect(audioURL: audioURL, bpOptions: bpOptions)
        }
    }

    // MARK: - Direct mode (no stem splitting)

    private func runDirect(audioURL: URL, bpOptions: BasicPitchOptions) throws {
        let outputURL = resolveOutputURL(audioURL: audioURL, suffix: nil)
        try checkOverwrite(outputURL)

        print("Loading model...")
        let bp = try BasicPitch()

        var options = bpOptions
        options.progressHandler = progressHandler

        print("Processing: \(audioURL.lastPathComponent)")
        let result = try bp.predict(audioURL: audioURL, options: options)
        try result.writeMIDI(to: outputURL)

        printSummary(result.noteEvents)
        print("Saved: \(outputURL.path)")
    }

    // MARK: - Stem-split mode

    private func runWithStems(audioURL: URL, bpOptions: BasicPitchOptions) throws {
        let requestedStems: Set<String>?
        if let stemsFilter {
            requestedStems = Set(stemsFilter.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        } else {
            requestedStems = nil
        }

        var options = StemTranscriptionOptions(
            stems: requestedStems,
            basicPitchOptions: bpOptions,
            outputMode: multiTrack ? .multiTrackMIDI : .separateFiles
        )
        options.basicPitchOptions.progressHandler = progressHandler

        print("Loading models (Demucs: \(stemModel), BasicPitch)...")
        let transcriber = try StemTranscriber(demucsModelName: stemModel)

        print("Processing: \(audioURL.lastPathComponent)")
        let result = try transcriber.transcribe(fileAt: audioURL, options: options) { stage in
            print("\r\u{1B}[K\(stage)", terminator: "")
            fflush(stdout)
        }
        print()

        if multiTrack {
            let outputURL = resolveOutputURL(audioURL: audioURL, suffix: nil)
            try checkOverwrite(outputURL)
            try result.write(to: outputURL)
            print("\nMulti-track MIDI with \(result.perStem.count) stems:")
            for (stemName, stemResult) in result.perStem.sorted(by: { $0.key < $1.key }) {
                print("  \(stemName): \(stemResult.noteEvents.count) notes")
            }
            print("Saved: \(outputURL.path)")
        } else {
            let outputURL = resolveOutputURL(audioURL: audioURL, suffix: nil)
            try result.write(to: outputURL)
            print("\nSeparate MIDI files:")
            for (stemName, stemResult) in result.perStem.sorted(by: { $0.key < $1.key }) {
                let baseName = outputURL.deletingPathExtension().lastPathComponent
                let dir = outputURL.deletingLastPathComponent()
                let stemURL = dir.appendingPathComponent("\(baseName)_\(stemName).mid")
                print("  \(stemName): \(stemResult.noteEvents.count) notes → \(stemURL.path)")
            }
        }
    }

    // MARK: - Helpers

    private func makeBasicPitchOptions() -> BasicPitchOptions {
        var options = BasicPitchOptions()
        options.onsetThreshold = onsetThreshold
        options.frameThreshold = frameThreshold
        options.minimumNoteLengthMS = minNoteLength
        options.minimumFrequency = minFreq
        options.maximumFrequency = maxFreq
        options.midiTempo = tempo
        options.includePitchBends = !noPitchBends
        options.multiplePitchBends = multiPitchBends
        options.melodiaTrick = !noMelodia
        return options
    }

    private func resolveInputURL() -> URL {
        let path = (input as NSString).expandingTildeInPath
        return URL(fileURLWithPath: path)
    }

    private func resolveOutputURL(audioURL: URL, suffix: String?) -> URL {
        if let output {
            let path = (output as NSString).expandingTildeInPath
            return URL(fileURLWithPath: path)
        }
        let stem = audioURL.deletingPathExtension().lastPathComponent
        let directory = audioURL.deletingLastPathComponent()
        let name = suffix != nil ? "\(stem)_\(suffix!)" : stem
        return directory.appendingPathComponent(name).appendingPathExtension("mid")
    }

    private func checkOverwrite(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) && !forceOverwrite {
            print("Output file already exists: \(url.path)")
            print("Overwrite? [y/N] ", terminator: "")
            guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                print("Aborted.")
                throw ExitCode.failure
            }
        }
    }

    private var progressHandler: (Int, Int) -> Void {
        { current, total in
            print("\rProcessing: window \(current)/\(total)", terminator: "")
            fflush(stdout)
            if current == total { print() }
        }
    }

    private func printSummary(_ events: [NoteEventWithTime]) {
        print("Notes detected: \(events.count)")
        guard !events.isEmpty else { return }
        let pitches = events.map(\.midiPitch)
        let first = events.min(by: { $0.startTime < $1.startTime })!
        let last = events.max(by: { $0.endTime < $1.endTime })!
        print("  Time range: \(String(format: "%.2f", first.startTime))s – \(String(format: "%.2f", last.endTime))s")
        print("  Pitch range: MIDI \(pitches.min()!) – \(pitches.max()!)")
    }
}
