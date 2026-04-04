// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import XCTest
@testable import BasicPitch

final class AudioWindowerTests: XCTestCase {
    func testSingleWindow() {
        // Audio shorter than one window
        let audio = [Float](repeating: 0.5, count: 1000)
        let result = AudioWindower.window(audio: audio)
        XCTAssertEqual(result.originalLength, 1000)
        XCTAssertGreaterThanOrEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows[0].count, Constants.audioNSamples)
    }

    func testWindowCount() {
        // Audio of exactly 2 hops worth (accounting for padding)
        let hopSize = Constants.hopSize
        let audioLen = hopSize * 2
        let audio = [Float](repeating: 0.1, count: audioLen)
        let result = AudioWindower.window(audio: audio)

        // With padding of 3840, total padded length = 3840 + audioLen
        // Windows are created for i = 0, hopSize, 2*hopSize, ... while i < paddedLen
        let paddedLen = 3840 + audioLen
        var expectedWindows = 0
        var i = 0
        while i < paddedLen {
            expectedWindows += 1
            i += hopSize
        }
        XCTAssertEqual(result.windows.count, expectedWindows)
    }

    func testPaddingPreserved() {
        // First 3840 samples of first window should be zeros (from prepended padding)
        let audio = [Float](repeating: 1.0, count: Constants.audioNSamples)
        let result = AudioWindower.window(audio: audio)
        let firstWindow = result.windows[0]
        // First 3840 should be zero (padding)
        for i in 0..<3840 {
            XCTAssertEqual(firstWindow[i], 0, "Expected zero at index \(i)")
        }
        // After padding, should be 1.0
        XCTAssertEqual(firstWindow[3840], 1.0)
    }

    func testLastWindowZeroPadded() {
        // Short audio that needs zero-padding in the last window
        let audio = [Float](repeating: 0.5, count: 100)
        let result = AudioWindower.window(audio: audio)
        let lastWindow = result.windows.last!
        XCTAssertEqual(lastWindow.count, Constants.audioNSamples)
    }
}
