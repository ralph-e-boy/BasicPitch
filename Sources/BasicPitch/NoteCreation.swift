// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import Foundation
import Accelerate

public struct NoteEvent: Sendable {
    public let startFrame: Int
    public let endFrame: Int
    public let midiPitch: Int
    public let amplitude: Float
}

public enum NoteCreation {

    // MARK: - Main entry point

    /// Port of `output_to_notes_polyphonic` from note_creation.py.
    public static func outputToNotesPolyphonic(
        frames inputFrames: Matrix,
        onsets inputOnsets: Matrix,
        onsetThresh: Float,
        frameThresh: Float,
        minNoteLen: Int = Constants.defaultMinNoteLen,
        inferOnsets: Bool = true,
        maxFreq: Float? = nil,
        minFreq: Float? = nil,
        melodiaTrick: Bool = true,
        energyTol: Int = Constants.energyTolerance
    ) -> [NoteEvent] {
        var frames = inputFrames
        var onsets = inputOnsets
        let nFrames = frames.rows
        let cols = frames.cols

        // Constrain frequency
        constrainFrequency(onsets: &onsets, frames: &frames, maxFreq: maxFreq, minFreq: minFreq)

        // Infer onsets from frame differences
        if inferOnsets {
            onsets = getInferredOnsets(onsets: onsets, frames: frames)
        }

        // Find onset peaks (equivalent to scipy.signal.argrelmax(onsets, axis=0))
        // For each column, find rows where value > both neighbors
        var peakThreshMat = Matrix(rows: onsets.rows, cols: cols)
        onsets.data.withUnsafeBufferPointer { src in
            peakThreshMat.data.withUnsafeMutableBufferPointer { dst in
                for col in 0..<cols {
                    for row in 1..<(onsets.rows - 1) {
                        let idx = row * cols + col
                        let val = src[idx]
                        if val > src[idx - cols] && val > src[idx + cols] {
                            dst[idx] = val
                        }
                    }
                }
            }
        }

        // Collect onsets above threshold, sorted backwards in time
        var onsetPairs: [(time: Int, freq: Int)] = []
        onsetPairs.reserveCapacity(256)
        peakThreshMat.data.withUnsafeBufferPointer { buf in
            for i in 0..<buf.count {
                if buf[i] >= onsetThresh {
                    onsetPairs.append((i / cols, i % cols))
                }
            }
        }
        onsetPairs.sort { $0.time > $1.time }

        // Track energy
        var remainingEnergy = frames

        var noteEvents: [NoteEvent] = []

        // Loop over onsets
        for (noteStartIdx, freqIdx) in onsetPairs {
            if noteStartIdx >= nFrames - 1 { continue }

            var i = noteStartIdx + 1
            var k = 0
            while i < nFrames - 1 && k < energyTol {
                if remainingEnergy[i, freqIdx] < frameThresh {
                    k += 1
                } else {
                    k = 0
                }
                i += 1
            }
            i -= k

            if i - noteStartIdx <= minNoteLen { continue }

            // Zero out energy in column and adjacent columns
            zeroEnergyRange(&remainingEnergy, freqIdx: freqIdx, fromRow: noteStartIdx, toRow: i)

            let amplitude = frames.meanOfColumn(freqIdx, fromRow: noteStartIdx, toRow: i)
            noteEvents.append(NoteEvent(
                startFrame: noteStartIdx,
                endFrame: i,
                midiPitch: freqIdx + Constants.midiOffset,
                amplitude: amplitude
            ))
        }

        // Melodia trick
        if melodiaTrick {
            var (iMid, freqIdx) = remainingEnergy.argmax()
            while remainingEnergy[iMid, freqIdx] > frameThresh {
                remainingEnergy[iMid, freqIdx] = 0

                // Forward pass
                var iFwd = iMid + 1
                var kFwd = 0
                while iFwd < nFrames - 1 && kFwd < energyTol {
                    if remainingEnergy[iFwd, freqIdx] < frameThresh {
                        kFwd += 1
                    } else {
                        kFwd = 0
                    }
                    remainingEnergy[iFwd, freqIdx] = 0
                    if freqIdx < Constants.maxFreqIdx {
                        remainingEnergy[iFwd, freqIdx + 1] = 0
                    }
                    if freqIdx > 0 {
                        remainingEnergy[iFwd, freqIdx - 1] = 0
                    }
                    iFwd += 1
                }
                let iEnd = iFwd - 1 - kFwd

                // Backward pass
                var iBwd = iMid - 1
                var kBwd = 0
                while iBwd > 0 && kBwd < energyTol {
                    if remainingEnergy[iBwd, freqIdx] < frameThresh {
                        kBwd += 1
                    } else {
                        kBwd = 0
                    }
                    remainingEnergy[iBwd, freqIdx] = 0
                    if freqIdx < Constants.maxFreqIdx {
                        remainingEnergy[iBwd, freqIdx + 1] = 0
                    }
                    if freqIdx > 0 {
                        remainingEnergy[iBwd, freqIdx - 1] = 0
                    }
                    iBwd -= 1
                }
                let iStart = iBwd + 1 + kBwd

                if iEnd - iStart <= minNoteLen {
                    (iMid, freqIdx) = remainingEnergy.argmax()
                    continue
                }

                let amplitude = frames.meanOfColumn(freqIdx, fromRow: iStart, toRow: iEnd)
                noteEvents.append(NoteEvent(
                    startFrame: iStart,
                    endFrame: iEnd,
                    midiPitch: freqIdx + Constants.midiOffset,
                    amplitude: amplitude
                ))
                (iMid, freqIdx) = remainingEnergy.argmax()
            }
        }

        return noteEvents
    }

    // MARK: - Frame-to-time conversion

    /// Port of `model_frames_to_time` from note_creation.py. Vectorized with vDSP.
    public static func modelFramesToTime(nFrames: Int) -> [Double] {
        let sr = Double(Constants.audioSampleRate)
        let hop = Double(Constants.fftHop)
        let annotNFrames = Double(Constants.annotNFrames)
        let audioNSamples = Double(Constants.audioNSamples)
        let windowOffset = (hop / sr) * (annotNFrames - (audioNSamples / hop)) + Constants.magicAlignmentOffset
        let hopOverSr = hop / sr

        var times = [Double](repeating: 0, count: nFrames)
        for i in 0..<nFrames {
            let originalTime = Double(i) * hopOverSr
            let windowNumber = floor(Double(i) / annotNFrames)
            times[i] = originalTime - (windowOffset * windowNumber)
        }
        return times
    }

    // MARK: - Helpers

    /// Constrain frequency range by zeroing out bins outside [minFreq, maxFreq].
    static func constrainFrequency(
        onsets: inout Matrix,
        frames: inout Matrix,
        maxFreq: Float?,
        minFreq: Float?
    ) {
        let nFreqs = onsets.cols
        var minFreqIdx = 0
        var maxFreqIdx = nFreqs

        if let minFreq = minFreq {
            minFreqIdx = Int(round(hzToMidi(Float64(minFreq)))) - Constants.midiOffset
        }
        if let maxFreq = maxFreq {
            maxFreqIdx = Int(round(hzToMidi(Float64(maxFreq)))) - Constants.midiOffset
        }

        onsets.zeroOutColumns(below: minFreqIdx, above: maxFreqIdx)
        frames.zeroOutColumns(below: minFreqIdx, above: maxFreqIdx)
    }

    /// Port of `get_infered_onsets` from note_creation.py. Uses vDSP for vectorized ops.
    static func getInferredOnsets(onsets: Matrix, frames: Matrix) -> Matrix {
        let nDiff = 2
        let rows = frames.rows
        let cols = frames.cols
        let count = rows * cols

        // Compute frame diffs for n=1 and n=2, then take element-wise minimum.
        // diff_n[r,c] = frames[r,c] - frames[r-n,c]  (treating out-of-bounds as 0)
        var diff1 = [Float](repeating: 0, count: count)
        var diff2 = [Float](repeating: 0, count: count)

        frames.data.withUnsafeBufferPointer { src in
            diff1.withUnsafeMutableBufferPointer { d1 in
                diff2.withUnsafeMutableBufferPointer { d2 in
                    // n=1: diff1[r,c] = frames[r,c] - frames[r-1,c]
                    // Row 0: diff = frames[0,c] - 0 = frames[0,c]
                    memcpy(d1.baseAddress!, src.baseAddress!, count * MemoryLayout<Float>.size)
                    // Subtract shifted: diff1[cols..] = frames[cols..] - frames[0..]
                    vDSP_vsub(src.baseAddress!, 1,
                              src.baseAddress!.advanced(by: cols), 1,
                              d1.baseAddress!.advanced(by: cols), 1,
                              vDSP_Length(count - cols))

                    // n=2: diff2[r,c] = frames[r,c] - frames[r-2,c]
                    memcpy(d2.baseAddress!, src.baseAddress!, count * MemoryLayout<Float>.size)
                    if count > 2 * cols {
                        vDSP_vsub(src.baseAddress!, 1,
                                  src.baseAddress!.advanced(by: 2 * cols), 1,
                                  d2.baseAddress!.advanced(by: 2 * cols), 1,
                                  vDSP_Length(count - 2 * cols))
                    }
                }
            }
        }

        // Element-wise minimum of diff1 and diff2
        var frameDiff = [Float](repeating: 0, count: count)
        vDSP.minimum(diff1, diff2, result: &frameDiff)

        // Clamp negatives to 0
        vDSP.clip(frameDiff, to: 0...Float.greatestFiniteMagnitude, result: &frameDiff)

        // Zero first nDiff rows
        frameDiff.withUnsafeMutableBufferPointer { buf in
            _ = memset(buf.baseAddress!, 0, nDiff * cols * MemoryLayout<Float>.size)
        }

        // Rescale to match max of onsets
        let maxOnsets = vDSP.maximum(onsets.data)
        let maxDiff = vDSP.maximum(frameDiff)
        if maxDiff > 0 {
            let scale = maxOnsets / maxDiff
            vDSP.multiply(scale, frameDiff, result: &frameDiff)
        }

        // Element-wise max of onsets and frameDiff
        var result = [Float](repeating: 0, count: count)
        vDSP.maximum(onsets.data, frameDiff, result: &result)

        return Matrix(rows: rows, cols: cols, data: result)
    }

    /// Hz to MIDI note number: 12 * log2(f/440) + 69
    static func hzToMidi(_ hz: Float64) -> Float64 {
        12.0 * log2(hz / 440.0) + 69.0
    }

    /// Zero energy in a column and its neighbors across a row range.
    @inline(__always)
    private static func zeroEnergyRange(_ energy: inout Matrix, freqIdx: Int, fromRow: Int, toRow: Int) {
        energy.zeroColumn(freqIdx, fromRow: fromRow, toRow: toRow)
        if freqIdx < Constants.maxFreqIdx {
            energy.zeroColumn(freqIdx + 1, fromRow: fromRow, toRow: toRow)
        }
        if freqIdx > 0 {
            energy.zeroColumn(freqIdx - 1, fromRow: fromRow, toRow: toRow)
        }
    }
}
