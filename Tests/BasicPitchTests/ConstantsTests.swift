// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import XCTest
@testable import BasicPitch

final class ConstantsTests: XCTestCase {
    func testDerivedConstants() {
        XCTAssertEqual(Constants.audioNSamples, 43844)
        XCTAssertEqual(Constants.annotationsFPS, 86)
        XCTAssertEqual(Constants.annotNFrames, 172)
        XCTAssertEqual(Constants.nFreqBinsNotes, 88)
        XCTAssertEqual(Constants.nFreqBinsContours, 264)
        XCTAssertEqual(Constants.overlapLen, 7680)
        XCTAssertEqual(Constants.hopSize, 36164)
    }

    func testFreqBins() {
        let notesBins = Constants.freqBinsNotes
        XCTAssertEqual(notesBins.count, 88)
        XCTAssertEqual(notesBins[0], 27.5, accuracy: 0.01)

        let contoursBins = Constants.freqBinsContours
        XCTAssertEqual(contoursBins.count, 264)
        XCTAssertEqual(contoursBins[0], 27.5, accuracy: 0.01)
    }
}
