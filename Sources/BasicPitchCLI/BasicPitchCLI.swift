// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import ArgumentParser
import BasicPitch
import Foundation

@main
struct BasicPitchCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "basic-pitch-cli",
        abstract: "Convert audio to MIDI using the Basic Pitch neural network.",
        discussion: """
            Accepts local files or remote URLs. Supports any format AVFoundation \
            can decode: WAV, MP3, M4A/AAC, AIFF, CAF, FLAC, etc.

            Examples:
              basic-pitch-cli song.wav
              basic-pitch-cli song.mp3 -o output.mid
              basic-pitch-cli https://example.com/audio.wav
              basic-pitch-cli recording.m4a --onset-threshold 0.6 --no-pitch-bends
            """
    )

    @Argument(help: "Audio file path or remote URL.")
    var input: String

    @Option(name: [.short, .customLong("output")], help: "Output MIDI file path. Defaults to <input>.mid in the same directory.")
    var output: String?

    @Flag(name: .customLong("yes"), help: "Overwrite output without asking.")
    var forceOverwrite = false

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

    @Flag(name: .customLong("multi-pitch-bends"), help: "Allow overlapping notes to have independent pitch bends (uses multi-track MIDI).")
    var multiPitchBends = false

    @Flag(name: .customLong("no-melodia"), help: "Disable the melodia post-processing trick.")
    var noMelodia = false

    mutating func run() throws {
        let audioURL = try resolveInput(input)
        let outputURL = try resolveOutput(audioURL: audioURL)

        // Check overwrite
        if FileManager.default.fileExists(atPath: outputURL.path) && !forceOverwrite {
            print("Output file already exists: \(outputURL.path)")
            print("Overwrite? [y/N] ", terminator: "")
            guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                print("Aborted.")
                throw ExitCode.failure
            }
        }

        // Load model
        print("Loading model...")
        let bp = try BasicPitch()

        // Configure options
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
        options.progressHandler = { current, total in
            print("\rProcessing: window \(current)/\(total)", terminator: "")
            fflush(stdout)
            if current == total { print() }
        }

        // Run prediction
        print("Processing: \(audioURL.lastPathComponent)")
        let result = try bp.predict(audioURL: audioURL, options: options)

        // Write output
        try result.writeMIDI(to: outputURL)

        print("Notes detected: \(result.noteEvents.count)")
        if !result.noteEvents.isEmpty {
            let pitches = result.noteEvents.map(\.midiPitch)
            let minP = pitches.min()!
            let maxP = pitches.max()!
            let first = result.noteEvents.min(by: { $0.startTime < $1.startTime })!
            let last = result.noteEvents.max(by: { $0.endTime < $1.endTime })!
            print("  Time range: \(String(format: "%.2f", first.startTime))s – \(String(format: "%.2f", last.endTime))s")
            print("  Pitch range: MIDI \(minP) – \(maxP)")

            // Note distribution by octave
            let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            for octave in 0...8 {
                let lo = 12 + octave * 12  // C0=12, C1=24, ...
                let hi = lo + 11
                let count = pitches.filter { $0 >= lo && $0 <= hi }.count
                if count > 0 {
                    print("    \(noteNames[0])\(octave)–\(noteNames[11])\(octave) (MIDI \(lo)–\(hi)): \(count) notes")
                }
            }
        }
        print("Saved: \(outputURL.path)")

        // Clean up temp file if we downloaded
        if audioURL.path.contains(NSTemporaryDirectory()) {
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    // MARK: - Input resolution

    private func resolveInput(_ input: String) throws -> URL {
        // Check if it's a URL
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            guard let remoteURL = URL(string: input) else {
                throw ValidationError("Invalid URL: \(input)")
            }
            return try downloadFile(from: remoteURL)
        }

        // Local file
        let path = (input as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("File not found: \(url.path)")
        }
        return url
    }

    private func downloadFile(from url: URL) throws -> URL {
        print("Downloading: \(url.absoluteString)")

        let semaphore = DispatchSemaphore(value: 0)
        var resultURL: URL?
        var downloadError: Error?

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            defer { semaphore.signal() }
            if let error = error {
                downloadError = error
                return
            }
            guard let tempURL = tempURL else {
                downloadError = ValidationError("Download returned no data")
                return
            }
            // Move to a temp location with the original extension
            let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                resultURL = dest
            } catch {
                downloadError = error
            }
        }
        task.resume()
        semaphore.wait()

        if let error = downloadError {
            throw ValidationError("Download failed: \(error.localizedDescription)")
        }
        guard let url = resultURL else {
            throw ValidationError("Download failed: no file produced")
        }
        print("Downloaded to temp file.")
        return url
    }

    // MARK: - Output resolution

    private func resolveOutput(audioURL: URL) throws -> URL {
        if let output = output {
            let path = (output as NSString).expandingTildeInPath
            return URL(fileURLWithPath: path)
        }

        // Default: same directory and stem as input, with .mid extension
        // For remote downloads, use current directory
        let stem: String
        let directory: URL

        if audioURL.path.contains(NSTemporaryDirectory()) {
            // Downloaded file — output to current directory with original name
            let originalName = URL(string: input)?.deletingPathExtension().lastPathComponent ?? "output"
            stem = originalName
            directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        } else {
            stem = audioURL.deletingPathExtension().lastPathComponent
            directory = audioURL.deletingLastPathComponent()
        }

        return directory.appendingPathComponent(stem).appendingPathExtension("mid")
    }
}
