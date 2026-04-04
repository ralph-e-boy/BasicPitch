// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import XCTest
@testable import BasicPitch

final class IntegrationTests: XCTestCase {
    func testFullPipeline() throws {
        guard let audioURL = Bundle.module.url(forResource: "vocadito_10", withExtension: "wav") else {
            XCTFail("Test audio file not found in bundle")
            return
        }

        let bp = try BasicPitch()
        let result = try bp.predict(audioURL: audioURL)

        // Should produce note events
        XCTAssertGreaterThan(result.noteEvents.count, 0, "Should detect at least one note")

        // All MIDI pitches should be in valid piano range
        for event in result.noteEvents {
            XCTAssertGreaterThanOrEqual(event.midiPitch, 21, "MIDI pitch below piano range")
            XCTAssertLessThanOrEqual(event.midiPitch, 108, "MIDI pitch above piano range")
            XCTAssertGreaterThan(event.endTime, event.startTime, "Note should have positive duration")
            XCTAssertGreaterThan(event.amplitude, 0, "Note should have positive amplitude")
        }

        // MIDI data should be valid (starts with MThd)
        XCTAssertGreaterThan(result.midiData.count, 14)
        let header = Array(result.midiData.prefix(4))
        XCTAssertEqual(header, [0x4D, 0x54, 0x68, 0x64], "MIDI should start with MThd")
    }

    func testDeterminism() throws {
        guard let audioURL = Bundle.module.url(forResource: "vocadito_10", withExtension: "wav") else {
            XCTFail("Test audio file not found in bundle")
            return
        }

        let bp = try BasicPitch()
        let result1 = try bp.predict(audioURL: audioURL)
        let result2 = try bp.predict(audioURL: audioURL)

        XCTAssertEqual(result1.noteEvents.count, result2.noteEvents.count, "Should produce same number of notes")
        XCTAssertEqual(result1.midiData, result2.midiData, "MIDI output should be identical")
    }

    func testWriteMIDIToFile() throws {
        guard let audioURL = Bundle.module.url(forResource: "vocadito_10", withExtension: "wav") else {
            XCTFail("Test audio file not found in bundle")
            return
        }

        let bp = try BasicPitch()
        let result = try bp.predict(audioURL: audioURL)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("basicpitch_test_\(UUID()).mid")
        try result.writeMIDI(to: tmpURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpURL.path))
        let fileData = try Data(contentsOf: tmpURL)
        XCTAssertEqual(fileData, result.midiData)

        try FileManager.default.removeItem(at: tmpURL)
    }

    func testSilence() throws {
        // Create a silent WAV file
        let tmpDir = FileManager.default.temporaryDirectory
        let silentURL = tmpDir.appendingPathComponent("silence_\(UUID()).wav")
        try createSilentWAV(url: silentURL, durationSeconds: 1.0)

        let bp = try BasicPitch()
        let result = try bp.predict(audioURL: silentURL)

        // Silence should produce zero or very few notes
        XCTAssertLessThanOrEqual(result.noteEvents.count, 2, "Silence should produce very few notes")

        try FileManager.default.removeItem(at: silentURL)
    }

    // MARK: - Helpers

    private func createSilentWAV(url: URL, durationSeconds: Double) throws {
        let sampleRate: UInt32 = 22050
        let numSamples = UInt32(durationSeconds * Double(sampleRate))
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = numSamples * UInt32(blockAlign)

        var data = Data()
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: (36 + dataSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        data.append(contentsOf: [UInt8](repeating: 0, count: Int(dataSize)))

        try data.write(to: url)
    }
}
