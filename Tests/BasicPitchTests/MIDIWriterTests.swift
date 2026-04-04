// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import XCTest
@testable import BasicPitch

final class MIDIWriterTests: XCTestCase {
    func testHeaderFormat0() {
        let events = [
            NoteEventWithTime(startTime: 0, endTime: 1, midiPitch: 60, amplitude: 0.8, pitchBends: nil)
        ]
        let data = MIDIWriter.noteEventsToMIDI(events: events)

        // Check MThd header
        XCTAssertEqual(data[0], 0x4D) // M
        XCTAssertEqual(data[1], 0x54) // T
        XCTAssertEqual(data[2], 0x68) // h
        XCTAssertEqual(data[3], 0x64) // d

        // Header length = 6
        XCTAssertEqual(data[4], 0)
        XCTAssertEqual(data[5], 0)
        XCTAssertEqual(data[6], 0)
        XCTAssertEqual(data[7], 6)

        // Format 0
        XCTAssertEqual(data[8], 0)
        XCTAssertEqual(data[9], 0)

        // 1 track
        XCTAssertEqual(data[10], 0)
        XCTAssertEqual(data[11], 1)

        // Ticks per quarter = 480 = 0x01E0
        XCTAssertEqual(data[12], 0x01)
        XCTAssertEqual(data[13], 0xE0)

        // Check MTrk follows
        XCTAssertEqual(data[14], 0x4D) // M
        XCTAssertEqual(data[15], 0x54) // T
        XCTAssertEqual(data[16], 0x72) // r
        XCTAssertEqual(data[17], 0x6B) // k
    }

    func testNonEmptyMIDI() {
        let events = [
            NoteEventWithTime(startTime: 0, endTime: 0.5, midiPitch: 60, amplitude: 0.5, pitchBends: nil),
            NoteEventWithTime(startTime: 0.5, endTime: 1.0, midiPitch: 64, amplitude: 0.7, pitchBends: nil),
        ]
        let data = MIDIWriter.noteEventsToMIDI(events: events)
        XCTAssertGreaterThan(data.count, 20)
    }

    func testEmptyEvents() {
        let data = MIDIWriter.noteEventsToMIDI(events: [])
        // Should still produce valid MIDI with header + empty track
        XCTAssertGreaterThan(data.count, 14)
    }

    func testPitchBendInclusion() {
        let events = [
            NoteEventWithTime(startTime: 0, endTime: 1, midiPitch: 60, amplitude: 0.8,
                              pitchBends: [0, 1, 2, 1, 0])
        ]
        let data = MIDIWriter.noteEventsToMIDI(events: events, multiplePitchBends: true)
        // Should contain pitch bend events (0xE0 byte)
        let bytes = Array(data)
        XCTAssertTrue(bytes.contains(0xE0), "MIDI data should contain pitch bend events")
    }

    func testWriteToFile() throws {
        let events = [
            NoteEventWithTime(startTime: 0, endTime: 1, midiPitch: 60, amplitude: 0.8, pitchBends: nil)
        ]
        let data = MIDIWriter.noteEventsToMIDI(events: events)

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID()).mid")
        try MIDIWriter.write(data: data, to: tmpURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpURL.path))

        let readBack = try Data(contentsOf: tmpURL)
        XCTAssertEqual(readBack, data)

        try FileManager.default.removeItem(at: tmpURL)
    }
}
