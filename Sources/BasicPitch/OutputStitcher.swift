// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import Foundation

public struct StitchedOutput: Sendable {
    public let notes: Matrix    // (totalFrames, 88)
    public let onsets: Matrix   // (totalFrames, 88)
    public let contours: Matrix // (totalFrames, 264)
}

public enum OutputStitcher {
    /// Port of `unwrap_output` from inference.py.
    /// Removes overlap frames, concatenates into pre-allocated buffers, and trims.
    public static func stitch(
        predictions: [WindowPrediction],
        originalLength: Int
    ) -> StitchedOutput {
        let nOlap = Constants.defaultOverlappingFrames / 2 // 15
        let framesPerWindow = Constants.annotNFrames - Constants.defaultOverlappingFrames // 142
        let hopSize = Constants.hopSize

        // Calculate final size upfront
        let nExpectedWindows = Double(originalLength) / Double(hopSize)
        let maxFrames = min(
            Int(nExpectedWindows * Double(framesPerWindow)),
            predictions.count * framesPerWindow
        )

        // Pre-allocate final buffers and copy directly — no intermediate arrays
        func stitchInto(_ extract: (WindowPrediction) -> Matrix) -> Matrix {
            let cols = extract(predictions[0]).cols
            let totalCount = maxFrames * cols
            var buffer = [Float](repeating: 0, count: totalCount)

            buffer.withUnsafeMutableBufferPointer { dst in
                var writeOffset = 0
                for pred in predictions {
                    let m = extract(pred)
                    let readStart = nOlap * cols
                    let readEnd = (m.rows - nOlap) * cols
                    guard readEnd > readStart else { continue }
                    let framesToCopy = min(readEnd - readStart, totalCount - writeOffset)
                    guard framesToCopy > 0 else { break }

                    m.data.withUnsafeBufferPointer { src in
                        memcpy(dst.baseAddress!.advanced(by: writeOffset),
                               src.baseAddress!.advanced(by: readStart),
                               framesToCopy * MemoryLayout<Float>.size)
                    }
                    writeOffset += framesToCopy
                }
            }

            return Matrix(rows: maxFrames, cols: cols, data: buffer)
        }

        return StitchedOutput(
            notes: stitchInto(\.notes),
            onsets: stitchInto(\.onsets),
            contours: stitchInto(\.contours)
        )
    }
}
