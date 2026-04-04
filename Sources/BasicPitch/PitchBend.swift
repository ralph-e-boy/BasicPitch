// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import Accelerate
import Foundation

public struct NoteEventWithBend: Sendable {
    public let startFrame: Int
    public let endFrame: Int
    public let midiPitch: Int
    public let amplitude: Float
    public let pitchBends: [Int]?
}

public struct NoteEventWithTime: Sendable {
    public let startTime: Double
    public let endTime: Double
    public let midiPitch: Int
    public let amplitude: Float
    public let pitchBends: [Int]?
}

public enum PitchBend {

    /// Port of `midi_pitch_to_contour_bin` from note_creation.py.
    static func midiPitchToContourBin(_ pitchMidi: Int) -> Double {
        let pitchHz = 440.0 * pow(2.0, (Double(pitchMidi) - 69.0) / 12.0)
        return 12.0 * Double(Constants.contoursBinsPerSemitone) * log2(pitchHz / Constants.annotationsBaseFrequency)
    }

    private static let defaultNBinsTolerance = 25
    private static let defaultWindowLength = defaultNBinsTolerance * 2 + 1 // 51
    private static let cachedGaussianFloat: [Float] = gaussianWindow(length: defaultWindowLength, std: 5.0).map { Float($0) }

    /// Port of `get_pitch_bends` from note_creation.py.
    public static func getPitchBends(
        contours: Matrix,
        noteEvents: [NoteEvent],
        nBinsTolerance: Int = 25
    ) -> [NoteEventWithBend] {
        let windowLength = nBinsTolerance * 2 + 1
        let freqGaussian: [Float] = (nBinsTolerance == defaultNBinsTolerance)
            ? cachedGaussianFloat
            : gaussianWindow(length: windowLength, std: 5.0).map { Float($0) }

        return noteEvents.map { note in
            let freqIdx = Int(round(midiPitchToContourBin(note.midiPitch)))
            let freqStartIdx = max(freqIdx - nBinsTolerance, 0)
            let freqEndIdx = min(Constants.nFreqBinsContours, freqIdx + nBinsTolerance + 1)

            let startFrame = note.startFrame
            let endFrame = min(note.endFrame, contours.rows)
            guard endFrame > startFrame && freqEndIdx > freqStartIdx else {
                return NoteEventWithBend(
                    startFrame: note.startFrame, endFrame: note.endFrame,
                    midiPitch: note.midiPitch, amplitude: note.amplitude, pitchBends: nil
                )
            }

            // Gaussian window slice
            let gaussStart = max(0, nBinsTolerance - freqIdx)
            let gaussEnd = windowLength - max(0, freqIdx - (Constants.nFreqBinsContours - nBinsTolerance - 1))
            let gaussSlice = Array(freqGaussian[gaussStart..<gaussEnd])

            let pbShift = nBinsTolerance - max(0, nBinsTolerance - freqIdx)

            // Extract submatrix and multiply by Gaussian, then argmax per row
            let subRows = endFrame - startFrame
            let subCols = freqEndIdx - freqStartIdx
            var bends = [Int](repeating: 0, count: subRows)

            contours.data.withUnsafeBufferPointer { contourBuf in
                var weighted = [Float](repeating: 0, count: subCols)
                for r in 0..<subRows {
                    let rowBase = (startFrame + r) * contours.cols + freqStartIdx
                    // Multiply row slice by Gaussian window
                    vDSP_vmul(contourBuf.baseAddress!.advanced(by: rowBase), 1,
                              gaussSlice, 1,
                              &weighted, 1,
                              vDSP_Length(subCols))
                    // Find argmax
                    var maxVal: Float = 0
                    var maxIdx: vDSP_Length = 0
                    vDSP_maxvi(weighted, 1, &maxVal, &maxIdx, vDSP_Length(subCols))
                    bends[r] = Int(maxIdx) - pbShift
                }
            }

            return NoteEventWithBend(
                startFrame: note.startFrame, endFrame: note.endFrame,
                midiPitch: note.midiPitch, amplitude: note.amplitude, pitchBends: bends
            )
        }
    }

    /// Port of `drop_overlapping_pitch_bends` from note_creation.py.
    public static func dropOverlappingPitchBends(_ events: [NoteEventWithTime]) -> [NoteEventWithTime] {
        var sorted = events.sorted { ($0.startTime, $0.endTime) < ($1.startTime, $1.endTime) }
        for i in 0..<sorted.count {
            guard i < sorted.count - 1 else { break }
            for j in (i + 1)..<sorted.count {
                if sorted[j].startTime >= sorted[i].endTime { break }
                sorted[i] = NoteEventWithTime(
                    startTime: sorted[i].startTime, endTime: sorted[i].endTime,
                    midiPitch: sorted[i].midiPitch, amplitude: sorted[i].amplitude, pitchBends: nil
                )
                sorted[j] = NoteEventWithTime(
                    startTime: sorted[j].startTime, endTime: sorted[j].endTime,
                    midiPitch: sorted[j].midiPitch, amplitude: sorted[j].amplitude, pitchBends: nil
                )
            }
        }
        return sorted
    }

    /// Compute a Gaussian window: exp(-0.5 * ((x - center) / std)^2)
    private static func gaussianWindow(length: Int, std: Double) -> [Double] {
        let center = Double(length - 1) / 2.0
        return (0..<length).map { i in
            let x = (Double(i) - center) / std
            return exp(-0.5 * x * x)
        }
    }
}
