import BasicPitch
import CoreML
import DemucsMLX
import Foundation

public enum StemOutputMode {
    /// One .mid file per stem
    case separateFiles
    /// Single multi-track MIDI with named tracks
    case multiTrackMIDI
}

public struct StemTranscriptionOptions {
    /// Which stems to transcribe. `nil` means all stems.
    public var stems: Set<String>?
    public var basicPitchOptions: BasicPitchOptions
    public var outputMode: StemOutputMode

    public init(
        stems: Set<String>? = nil,
        basicPitchOptions: BasicPitchOptions = BasicPitchOptions(),
        outputMode: StemOutputMode = .multiTrackMIDI
    ) {
        self.stems = stems
        self.basicPitchOptions = basicPitchOptions
        self.outputMode = outputMode
    }
}

/// Progress updates during transcription.
public enum StemTranscriptionStage: CustomStringConvertible {
    case separating(fraction: Float, stage: String, eta: TimeInterval?)
    case transcribing(stemName: String, stemIndex: Int, stemCount: Int)

    public var description: String {
        switch self {
        case .separating(let fraction, let stage, let eta):
            let pct = Int(fraction * 100)
            if let eta, eta > 0 {
                return "Separating stems: \(pct)% (\(stage)) – ~\(Int(eta))s remaining"
            }
            return "Separating stems: \(pct)% (\(stage))"
        case .transcribing(let name, let idx, let count):
            return "Transcribing stem \(idx + 1)/\(count): \(name)"
        }
    }
}

public struct StemTranscriptionResult {
    /// Per-stem transcription results (note events + individual MIDI data).
    public let perStem: [String: BasicPitchResult]
    /// Combined multi-track MIDI data. Populated only for `.multiTrackMIDI` mode.
    public let combinedMIDIData: Data?

    /// Write results to disk.
    /// For `.multiTrackMIDI`, writes a single file to `outputURL`.
    /// For `.separateFiles`, writes `<outputURL_stem>_<stemName>.mid` for each stem.
    public func write(to outputURL: URL) throws {
        if let combinedMIDIData {
            try combinedMIDIData.write(to: outputURL)
        } else {
            let baseName = outputURL.deletingPathExtension().lastPathComponent
            let directory = outputURL.deletingLastPathComponent()
            for (stemName, result) in perStem {
                let stemURL = directory.appendingPathComponent("\(baseName)_\(stemName).mid")
                try result.writeMIDI(to: stemURL)
            }
        }
    }
}

public final class StemTranscriber {
    private let separator: DemucsSeparator
    private let basicPitch: BasicPitch

    public init(
        demucsModelName: String = "htdemucs",
        demucsParameters: DemucsSeparationParameters = DemucsSeparationParameters(),
        demucsModelDirectory: URL? = nil,
        basicPitchConfiguration: MLModelConfiguration? = nil
    ) throws {
        self.separator = try DemucsSeparator(
            modelName: demucsModelName,
            parameters: demucsParameters,
            modelDirectory: demucsModelDirectory
        )
        self.basicPitch = try BasicPitch(configuration: basicPitchConfiguration)
    }

    /// Available stem names from the loaded Demucs model.
    public var availableStems: [String] {
        separator.sources
    }

    /// Split audio into stems, then transcribe each stem to MIDI.
    /// - Parameters:
    ///   - url: Path to the audio file.
    ///   - options: Transcription options.
    ///   - progressHandler: Called with status updates during separation and transcription.
    public func transcribe(
        fileAt url: URL,
        options: StemTranscriptionOptions = StemTranscriptionOptions(),
        progressHandler: ((StemTranscriptionStage) -> Void)? = nil
    ) throws -> StemTranscriptionResult {
        // 1. Separate stems using async API for progress, bridged with semaphore
        let separation: DemucsSeparationResult = try separateWithProgress(url: url, progressHandler: progressHandler)

        // 2. Determine which stems to process
        let stemNames: [String]
        if let requested = options.stems {
            stemNames = separator.sources.filter { requested.contains($0) }
        } else {
            stemNames = separator.sources
        }

        // 3. Transcribe each stem sequentially (to manage memory)
        var perStem: [String: BasicPitchResult] = [:]
        for (index, stemName) in stemNames.enumerated() {
            guard let stemAudio = separation.stems[stemName] else { continue }

            progressHandler?(.transcribing(stemName: stemName, stemIndex: index, stemCount: stemNames.count))

            let result = try basicPitch.predict(
                audioSamples: stemAudio.channelMajorSamples,
                channels: stemAudio.channels,
                sampleRate: stemAudio.sampleRate,
                options: options.basicPitchOptions
            )
            perStem[stemName] = result
        }

        // 4. Build combined MIDI if requested
        let combinedMIDIData: Data?
        switch options.outputMode {
        case .multiTrackMIDI:
            let stemEvents = stemNames.compactMap { name -> (stemName: String, events: [NoteEventWithTime])? in
                guard let result = perStem[name] else { return nil }
                return (stemName: name, events: result.noteEvents)
            }
            combinedMIDIData = MIDIWriter.stemEventsToMIDI(
                stemEvents: stemEvents,
                multiplePitchBends: options.basicPitchOptions.multiplePitchBends,
                midiTempo: options.basicPitchOptions.midiTempo
            )
        case .separateFiles:
            combinedMIDIData = nil
        }

        return StemTranscriptionResult(perStem: perStem, combinedMIDIData: combinedMIDIData)
    }

    // MARK: - Private

    private func separateWithProgress(
        url: URL,
        progressHandler: ((StemTranscriptionStage) -> Void)?
    ) throws -> DemucsSeparationResult {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()

        separator.separate(
            fileAt: url,
            cancelToken: nil,
            interpolateProgress: true,
            progress: { progress in
                progressHandler?(.separating(
                    fraction: progress.fraction,
                    stage: progress.stage,
                    eta: progress.estimatedTimeRemaining
                ))
            },
            completion: { result in
                box.result = result
                semaphore.signal()
            }
        )

        semaphore.wait()

        switch box.result! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

private final class ResultBox: @unchecked Sendable {
    var result: Result<DemucsSeparationResult, Error>?
}
