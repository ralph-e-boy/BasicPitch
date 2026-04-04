// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import Foundation

public enum Constants {
    public static let audioSampleRate: Int = 22050
    public static let fftHop: Int = 256
    public static let audioWindowLength: Int = 2
    public static let audioNChannels: Int = 1

    public static let annotationsFPS: Int = audioSampleRate / fftHop // 86
    public static let annotNFrames: Int = annotationsFPS * audioWindowLength // 172
    public static let audioNSamples: Int = audioSampleRate * audioWindowLength - fftHop // 43844

    public static let semitonesPerOctave: Int = 12
    public static let annotationsNSemitones: Int = 88
    public static let annotationsBaseFrequency: Double = 27.5

    public static let notesBinsPerSemitone: Int = 1
    public static let contoursBinsPerSemitone: Int = 3
    public static let nFreqBinsNotes: Int = annotationsNSemitones * notesBinsPerSemitone // 88
    public static let nFreqBinsContours: Int = annotationsNSemitones * contoursBinsPerSemitone // 264

    // Note creation constants
    public static let midiOffset: Int = 21
    public static let nPitchBendTicks: Int = 8192
    public static let maxFreqIdx: Int = 87
    public static let defaultMinNoteLen: Int = 11
    public static let energyTolerance: Int = 11
    public static let magicAlignmentOffset: Double = 0.0018
    public static let midiVelocityScale: Int = 127
    public static let pitchBendScale: Double = 4096

    // Inference defaults
    public static let defaultOnsetThreshold: Float = 0.4
    public static let defaultFrameThreshold: Float = 0.25
    public static let defaultMinimumNoteLengthMS: Float = 127.7
    public static let defaultOverlappingFrames: Int = 30
    public static let defaultMidiTempo: Float = 120

    // Derived inference constants
    public static let overlapLen: Int = defaultOverlappingFrames * fftHop // 7680
    public static let hopSize: Int = audioNSamples - overlapLen // 36164

    public static func freqBins(binsPerSemitone: Int, baseFrequency: Double, nSemitones: Int) -> [Double] {
        let d = pow(2.0, 1.0 / Double(semitonesPerOctave * binsPerSemitone))
        return (0..<(binsPerSemitone * nSemitones)).map { i in
            baseFrequency * pow(d, Double(i))
        }
    }

    public static let freqBinsNotes: [Double] = freqBins(
        binsPerSemitone: notesBinsPerSemitone,
        baseFrequency: annotationsBaseFrequency,
        nSemitones: annotationsNSemitones
    )

    public static let freqBinsContours: [Double] = freqBins(
        binsPerSemitone: contoursBinsPerSemitone,
        baseFrequency: annotationsBaseFrequency,
        nSemitones: annotationsNSemitones
    )
}
