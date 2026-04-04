// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import CoreML
import Foundation

public struct BasicPitchOptions {
    public var onsetThreshold: Float
    public var frameThreshold: Float
    public var minimumNoteLengthMS: Float
    public var minimumFrequency: Float?
    public var maximumFrequency: Float?
    public var includePitchBends: Bool
    public var multiplePitchBends: Bool
    public var melodiaTrick: Bool
    public var midiTempo: Float

    /// Called with (completedWindows, totalWindows) during inference.
    public var progressHandler: ((Int, Int) -> Void)?

    public init(
        onsetThreshold: Float = Constants.defaultOnsetThreshold,
        frameThreshold: Float = Constants.defaultFrameThreshold,
        minimumNoteLengthMS: Float = Constants.defaultMinimumNoteLengthMS,
        minimumFrequency: Float? = nil,
        maximumFrequency: Float? = nil,
        includePitchBends: Bool = true,
        multiplePitchBends: Bool = false,
        melodiaTrick: Bool = true,
        midiTempo: Float = Constants.defaultMidiTempo,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) {
        self.onsetThreshold = onsetThreshold
        self.frameThreshold = frameThreshold
        self.minimumNoteLengthMS = minimumNoteLengthMS
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency
        self.includePitchBends = includePitchBends
        self.multiplePitchBends = multiplePitchBends
        self.melodiaTrick = melodiaTrick
        self.midiTempo = midiTempo
        self.progressHandler = progressHandler
    }
}

public struct BasicPitchResult: Sendable {
    public let noteEvents: [NoteEventWithTime]
    public let midiData: Data

    public func writeMIDI(to url: URL) throws {
        try MIDIWriter.write(data: midiData, to: url)
    }
}

public final class BasicPitch: @unchecked Sendable {
    private let inference: CoreMLInference

    /// Load model from the SPM bundle.
    public init(configuration: MLModelConfiguration? = nil) throws {
        self.inference = try CoreMLInference(configuration: configuration)
    }

    /// Load model from a custom URL (either .mlpackage or .mlmodelc).
    public init(modelURL: URL, configuration: MLModelConfiguration? = nil) throws {
        self.inference = try CoreMLInference(modelURL: modelURL, configuration: configuration)
    }

    /// Run the full pipeline from raw audio samples.
    /// Samples are channel-major `[Float]` (e.g. from Demucs output).
    /// Automatically resamples to 22050 Hz mono.
    public func predict(
        audioSamples: [Float],
        channels: Int = 1,
        sampleRate: Int,
        options: BasicPitchOptions = BasicPitchOptions()
    ) throws -> BasicPitchResult {
        let audio = try AudioLoader.resampleToMono(audioSamples, channels: channels, sampleRate: sampleRate)
        return try predictFromMono22050(audio: audio, options: options)
    }

    /// Run the full audio-to-MIDI pipeline synchronously.
    public func predict(audioURL: URL, options: BasicPitchOptions = BasicPitchOptions()) throws -> BasicPitchResult {
        // 1. Load and window audio
        let audio = try AudioLoader.loadAudio(from: audioURL)
        return try predictFromMono22050(audio: audio, options: options)
    }

    /// Internal: run pipeline on mono 22050Hz audio.
    private func predictFromMono22050(audio: [Float], options: BasicPitchOptions) throws -> BasicPitchResult {
        let audioWindows = AudioWindower.window(audio: audio)

        // 2. Run inference — parallel across windows
        let predictions = try inference.predictBatch(
            windows: audioWindows.windows,
            progressHandler: options.progressHandler
        )

        // 3. Stitch overlapping outputs into contiguous matrices
        let stitched = OutputStitcher.stitch(
            predictions: predictions,
            originalLength: audioWindows.originalLength
        )

        // 4. Detect notes
        let minNoteLen = Int(round(
            options.minimumNoteLengthMS / 1000.0
            * Float(Constants.audioSampleRate) / Float(Constants.fftHop)
        ))

        let noteEvents = NoteCreation.outputToNotesPolyphonic(
            frames: stitched.notes,
            onsets: stitched.onsets,
            onsetThresh: options.onsetThreshold,
            frameThresh: options.frameThreshold,
            minNoteLen: minNoteLen,
            inferOnsets: true,
            maxFreq: options.maximumFrequency,
            minFreq: options.minimumFrequency,
            melodiaTrick: options.melodiaTrick
        )

        // 5. Pitch bends (map over note events functionally)
        let notesWithBends: [NoteEventWithBend] = options.includePitchBends
            ? PitchBend.getPitchBends(contours: stitched.contours, noteEvents: noteEvents)
            : noteEvents.map {
                NoteEventWithBend(startFrame: $0.startFrame, endFrame: $0.endFrame,
                                  midiPitch: $0.midiPitch, amplitude: $0.amplitude, pitchBends: nil)
              }

        // 6. Convert frame indices → seconds, then generate MIDI (fused functional chain)
        let times = NoteCreation.modelFramesToTime(nFrames: stitched.contours.rows)
        let lastTime = times.last ?? 0

        let timedEvents = notesWithBends.map { note -> NoteEventWithTime in
            NoteEventWithTime(
                startTime: note.startFrame < times.count ? times[note.startFrame] : 0,
                endTime: note.endFrame < times.count ? times[note.endFrame] : lastTime,
                midiPitch: note.midiPitch, amplitude: note.amplitude,
                pitchBends: note.pitchBends
            )
        }

        let midiData = MIDIWriter.noteEventsToMIDI(
            events: timedEvents,
            multiplePitchBends: options.multiplePitchBends,
            midiTempo: options.midiTempo
        )

        return BasicPitchResult(noteEvents: timedEvents, midiData: midiData)
    }

    /// Run the full pipeline asynchronously.
    public func predict(audioURL: URL, options: BasicPitchOptions = BasicPitchOptions()) async throws -> BasicPitchResult {
        try await Task.detached(priority: .userInitiated) {
            try self.predict(audioURL: audioURL, options: options)
        }.value
    }

    /// Run the full pipeline from raw audio samples asynchronously.
    public func predict(
        audioSamples: [Float],
        channels: Int = 1,
        sampleRate: Int,
        options: BasicPitchOptions = BasicPitchOptions()
    ) async throws -> BasicPitchResult {
        try await Task.detached(priority: .userInitiated) {
            try self.predict(audioSamples: audioSamples, channels: channels, sampleRate: sampleRate, options: options)
        }.value
    }
}
