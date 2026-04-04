// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import XCTest
@testable import BasicPitch

final class NoteCreationTests: XCTestCase {
    func testOnsetPeakDetection() {
        // Create a matrix with a clear onset peak at (5, 3)
        let rows = 20
        let cols = 10
        var onsetsData = [Float](repeating: 0, count: rows * cols)
        // Create a local maximum at row 5, col 3
        onsetsData[4 * cols + 3] = 0.3  // row 4
        onsetsData[5 * cols + 3] = 0.8  // row 5 (peak)
        onsetsData[6 * cols + 3] = 0.2  // row 6

        var framesData = [Float](repeating: 0, count: rows * cols)
        // Sustain energy at freq 3 from row 5 to row 18
        for r in 5..<18 {
            framesData[r * cols + 3] = 0.6
        }

        let onsets = Matrix(rows: rows, cols: cols, data: onsetsData)
        let frames = Matrix(rows: rows, cols: cols, data: framesData)

        let notes = NoteCreation.outputToNotesPolyphonic(
            frames: frames,
            onsets: onsets,
            onsetThresh: 0.5,
            frameThresh: 0.3,
            minNoteLen: 2,
            inferOnsets: false,
            melodiaTrick: false,
            energyTol: 3
        )

        XCTAssertEqual(notes.count, 1)
        if let note = notes.first {
            XCTAssertEqual(note.startFrame, 5)
            XCTAssertEqual(note.midiPitch, 3 + Constants.midiOffset)
            XCTAssertGreaterThan(note.amplitude, 0)
        }
    }

    func testMelodiaTrick() {
        // Energy blob with no onset — should be picked up by melodia trick
        let rows = 30
        let cols = 10
        let onsetsData = [Float](repeating: 0, count: rows * cols)
        var framesData = [Float](repeating: 0, count: rows * cols)

        // Sustained energy at freq 5 from row 5 to row 25
        for r in 5..<25 {
            framesData[r * cols + 5] = 0.7
        }

        let onsets = Matrix(rows: rows, cols: cols, data: onsetsData)
        let frames = Matrix(rows: rows, cols: cols, data: framesData)

        let notes = NoteCreation.outputToNotesPolyphonic(
            frames: frames,
            onsets: onsets,
            onsetThresh: 0.5,
            frameThresh: 0.3,
            minNoteLen: 2,
            inferOnsets: false,
            melodiaTrick: true,
            energyTol: 3
        )

        XCTAssertGreaterThan(notes.count, 0)
        if let note = notes.first {
            XCTAssertEqual(note.midiPitch, 5 + Constants.midiOffset)
        }
    }

    func testModelFramesToTime() {
        let times = NoteCreation.modelFramesToTime(nFrames: 172)
        XCTAssertEqual(times.count, 172)
        XCTAssertEqual(times[0], 0, accuracy: 0.001)
        // Each frame is ~FFT_HOP / SAMPLE_RATE seconds apart
        let expectedStep = Double(Constants.fftHop) / Double(Constants.audioSampleRate)
        XCTAssertEqual(times[1] - times[0], expectedStep, accuracy: 0.001)
    }

    func testInferredOnsets() {
        let rows = 10
        let cols = 5
        // Frames with a sudden jump at row 3
        var framesData = [Float](repeating: 0, count: rows * cols)
        for r in 3..<10 {
            framesData[r * cols + 2] = 0.8
        }
        let frames = Matrix(rows: rows, cols: cols, data: framesData)
        // Provide some nonzero onsets so rescaling doesn't multiply by 0
        var onsetsData = [Float](repeating: 0, count: rows * cols)
        onsetsData[3 * cols + 2] = 0.1
        let onsets = Matrix(rows: rows, cols: cols, data: onsetsData)

        let result = NoteCreation.getInferredOnsets(onsets: onsets, frames: frames)
        // The inferred onset at the jump point should be at least as large as the original
        XCTAssertGreaterThanOrEqual(result[3, 2], 0.1)
        // And the overall result should have nonzero values at the jump
        XCTAssertGreaterThan(result[3, 2], 0)
    }
}
