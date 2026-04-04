// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import XCTest
@testable import BasicPitch

final class OutputStitcherTests: XCTestCase {
    func testOverlapRemoval() {
        // Create 2 predictions with known values
        let notesData1 = (0..<(172 * 88)).map { Float($0 % 88) }
        let notesData2 = (0..<(172 * 88)).map { Float(($0 % 88) + 100) }
        let zeroOnsets = [Float](repeating: 0, count: 172 * 88)
        let zeroContours = [Float](repeating: 0, count: 172 * 264)

        let pred1 = WindowPrediction(
            notes: Matrix(rows: 172, cols: 88, data: notesData1),
            onsets: Matrix(rows: 172, cols: 88, data: zeroOnsets),
            contours: Matrix(rows: 172, cols: 264, data: zeroContours)
        )
        let pred2 = WindowPrediction(
            notes: Matrix(rows: 172, cols: 88, data: notesData2),
            onsets: Matrix(rows: 172, cols: 88, data: zeroOnsets),
            contours: Matrix(rows: 172, cols: 264, data: zeroContours)
        )

        // Use a large original length so we don't trim
        let result = OutputStitcher.stitch(
            predictions: [pred1, pred2],
            originalLength: Constants.hopSize * 10
        )

        // Each window: 172 frames, remove 15 from start and end = 142 frames
        // 2 windows * 142 = 284 frames (but may be trimmed)
        XCTAssertEqual(result.notes.cols, 88)
        XCTAssertGreaterThan(result.notes.rows, 0)
        XCTAssertLessThanOrEqual(result.notes.rows, 284)
    }

    func testTrimsToExpectedLength() {
        let zeroNotes = [Float](repeating: 0, count: 172 * 88)
        let zeroOnsets = [Float](repeating: 0, count: 172 * 88)
        let zeroContours = [Float](repeating: 0, count: 172 * 264)

        let pred = WindowPrediction(
            notes: Matrix(rows: 172, cols: 88, data: zeroNotes),
            onsets: Matrix(rows: 172, cols: 88, data: zeroOnsets),
            contours: Matrix(rows: 172, cols: 264, data: zeroContours)
        )

        // originalLength of exactly 1 hop
        let result = OutputStitcher.stitch(
            predictions: [pred],
            originalLength: Constants.hopSize
        )

        // Expected: int((hopSize / hopSize) * 142) = 142
        XCTAssertEqual(result.notes.rows, 142)
    }
}
