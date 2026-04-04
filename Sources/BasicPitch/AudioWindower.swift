// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import Foundation

public struct AudioWindows: Sendable {
    public let windows: [[Float]]
    public let originalLength: Int
}

public enum AudioWindower {
    /// Pad and window audio into overlapping chunks for model inference.
    /// Port of `get_audio_input` from inference.py.
    public static func window(audio: [Float]) -> AudioWindows {
        let overlapLen = Constants.overlapLen // 7680
        let hopSize = Constants.hopSize // 36164
        let windowSize = Constants.audioNSamples // 43844
        let originalLength = audio.count

        // Prepend overlap_len/2 zeros
        let padCount = overlapLen / 2 // 3840
        let paddedCount = padCount + audio.count

        // Estimate window count to pre-allocate
        var windowCount = 0
        var pos = 0
        while pos < paddedCount { windowCount += 1; pos += hopSize }

        var windows = [[Float]]()
        windows.reserveCapacity(windowCount)

        audio.withUnsafeBufferPointer { audioBuf in
            for wi in 0..<windowCount {
                let start = wi * hopSize // start index in padded space
                var window = [Float](repeating: 0, count: windowSize)

                // Determine which portion of this window overlaps with the audio data.
                // Padded layout: [zeros(padCount)] [audio(originalLength)]
                // Window reads padded[start ..< start+windowSize]
                let windowEnd = start + windowSize
                let audioStart = max(start, padCount) - padCount        // index into audio[]
                let audioEnd = min(windowEnd, paddedCount) - padCount    // index into audio[]
                let copyStart = max(start, padCount) - start             // offset in window[]

                if audioEnd > audioStart {
                    let count = audioEnd - audioStart
                    _ = window.withUnsafeMutableBufferPointer { dst in
                        memcpy(dst.baseAddress!.advanced(by: copyStart),
                               audioBuf.baseAddress!.advanced(by: audioStart),
                               count * MemoryLayout<Float>.size)
                    }
                }
                windows.append(window)
            }
        }

        return AudioWindows(windows: windows, originalLength: originalLength)
    }
}
