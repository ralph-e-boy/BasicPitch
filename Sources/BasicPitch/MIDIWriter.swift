// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import Foundation

/// Minimal Standard MIDI File (SMF) writer.
/// Supports Format 0 (single track) and Format 1 (multi-track for per-note pitch bends).
public enum MIDIWriter {

    private static let ticksPerQuarterNote: UInt16 = 480
    private static let electricPiano1Program: UInt8 = 4 // "Electric Piano 1" (0-indexed)

    /// Convert note events to MIDI file data.
    /// Port of `note_events_to_midi` from note_creation.py.
    public static func noteEventsToMIDI(
        events: [NoteEventWithTime],
        multiplePitchBends: Bool = false,
        midiTempo: Float = 120
    ) -> Data {
        var processedEvents = events
        if !multiplePitchBends {
            processedEvents = PitchBend.dropOverlappingPitchBends(processedEvents)
        }

        let ticksPerSecond = Double(midiTempo) / 60.0 * Double(ticksPerQuarterNote)

        if multiplePitchBends {
            return writeFormat1(events: processedEvents, ticksPerSecond: ticksPerSecond, midiTempo: midiTempo)
        } else {
            return writeFormat0(events: processedEvents, ticksPerSecond: ticksPerSecond, midiTempo: midiTempo)
        }
    }

    /// MIDI channel and GM program assignments for common stem names.
    public static let stemChannelMap: [String: (channel: UInt8, program: UInt8?)] = [
        "drums":  (9, nil),   // Channel 10 (0-indexed 9) = GM percussion, no program change
        "bass":   (0, 32),    // Acoustic Bass
        "vocals": (1, 52),    // Choir Aahs
        "other":  (2, 4),     // Electric Piano 1
        "guitar": (3, 25),    // Acoustic Guitar (Nylon)
        "piano":  (4, 0),     // Acoustic Grand Piano
    ]

    /// Convert per-stem note events into a single multi-track MIDI file.
    /// Each stem gets its own named track on a dedicated MIDI channel.
    public static func stemEventsToMIDI(
        stemEvents: [(stemName: String, events: [NoteEventWithTime])],
        multiplePitchBends: Bool = false,
        midiTempo: Float = 120
    ) -> Data {
        let ticksPerSecond = Double(midiTempo) / 60.0 * Double(ticksPerQuarterNote)

        var allTracks = [[MIDIEvent]]()

        // Track 0: tempo only
        var tempoTrack = [MIDIEvent]()
        tempoTrack.append(.tempo(bpm: midiTempo, tick: 0))
        tempoTrack.append(.endOfTrack(tick: 0))
        allTracks.append(tempoTrack)

        // Fallback channel counter for unknown stem names
        var nextFallbackChannel: UInt8 = 5

        for (stemName, events) in stemEvents {
            var processedEvents = events
            if !multiplePitchBends {
                processedEvents = PitchBend.dropOverlappingPitchBends(processedEvents)
            }

            let mapping = stemChannelMap[stemName]
            let channel: UInt8
            if let mapping {
                channel = mapping.channel
            } else {
                channel = nextFallbackChannel
                nextFallbackChannel = (nextFallbackChannel + 1) % 16
                if nextFallbackChannel == 9 { nextFallbackChannel = 10 } // skip drum channel
            }

            var trackEvents = [MIDIEvent]()

            // Track name meta-event
            trackEvents.append(.trackName(name: stemName, tick: 0))

            // Program change (skip for drums channel 9)
            if channel != 9 {
                let program = mapping?.program ?? electricPiano1Program
                trackEvents.append(.programChange(channel: channel, program: program, tick: 0))
            }

            for event in processedEvents {
                let startTick = UInt32(round(event.startTime * ticksPerSecond))
                let endTick = UInt32(round(event.endTime * ticksPerSecond))
                let velocity = UInt8(min(127, max(0, Int(round(Float(Constants.midiVelocityScale) * event.amplitude)))))
                let pitch = UInt8(clamping: event.midiPitch)

                trackEvents.append(.noteOn(channel: channel, pitch: pitch, velocity: velocity, tick: startTick))

                if let bends = event.pitchBends, !bends.isEmpty {
                    let bendTimes = linspace(start: event.startTime, end: event.endTime, count: bends.count)
                    for (i, bend) in bends.enumerated() {
                        var midiTicks = Int(round(Double(bend) * Constants.pitchBendScale / Double(Constants.contoursBinsPerSemitone)))
                        midiTicks = max(-Constants.nPitchBendTicks, min(Constants.nPitchBendTicks - 1, midiTicks))
                        let bendTick = UInt32(round(bendTimes[i] * ticksPerSecond))
                        trackEvents.append(.pitchBend(channel: channel, value: Int16(midiTicks), tick: bendTick))
                    }
                }

                trackEvents.append(.noteOff(channel: channel, pitch: pitch, tick: endTick))
            }

            let lastTick = trackEvents.max(by: { $0.tick < $1.tick })?.tick ?? 0
            trackEvents.append(.endOfTrack(tick: lastTick))
            allTracks.append(trackEvents)
        }

        return buildSMF(format: 1, tracks: allTracks)
    }

    /// Write MIDI data to a file URL.
    public static func write(data: Data, to url: URL) throws {
        do {
            try data.write(to: url)
        } catch {
            throw BasicPitchError.midiWriteFailed(error)
        }
    }

    // MARK: - Format 0 (single track)

    private static func writeFormat0(
        events: [NoteEventWithTime],
        ticksPerSecond: Double,
        midiTempo: Float
    ) -> Data {
        var trackEvents = [MIDIEvent]()

        // Tempo event at tick 0
        trackEvents.append(.tempo(bpm: midiTempo, tick: 0))
        // Program change
        trackEvents.append(.programChange(channel: 0, program: electricPiano1Program, tick: 0))

        for event in events {
            let startTick = UInt32(round(event.startTime * ticksPerSecond))
            let endTick = UInt32(round(event.endTime * ticksPerSecond))
            let velocity = UInt8(min(127, max(0, Int(round(Float(Constants.midiVelocityScale) * event.amplitude)))))
            let pitch = UInt8(clamping: event.midiPitch)

            trackEvents.append(.noteOn(channel: 0, pitch: pitch, velocity: velocity, tick: startTick))

            // Pitch bends
            if let bends = event.pitchBends, !bends.isEmpty {
                let bendTimes = linspace(start: event.startTime, end: event.endTime, count: bends.count)
                for (i, bend) in bends.enumerated() {
                    var midiTicks = Int(round(Double(bend) * Constants.pitchBendScale / Double(Constants.contoursBinsPerSemitone)))
                    midiTicks = max(-Constants.nPitchBendTicks, min(Constants.nPitchBendTicks - 1, midiTicks))
                    let bendTick = UInt32(round(bendTimes[i] * ticksPerSecond))
                    trackEvents.append(.pitchBend(channel: 0, value: Int16(midiTicks), tick: bendTick))
                }
            }

            trackEvents.append(.noteOff(channel: 0, pitch: pitch, tick: endTick))
        }

        // End of track
        let lastTick = trackEvents.max(by: { $0.tick < $1.tick })?.tick ?? 0
        trackEvents.append(.endOfTrack(tick: lastTick))

        return buildSMF(format: 0, tracks: [trackEvents])
    }

    // MARK: - Format 1 (multi-track for per-note pitch bends)

    private static func writeFormat1(
        events: [NoteEventWithTime],
        ticksPerSecond: Double,
        midiTempo: Float
    ) -> Data {
        // Group events by MIDI pitch
        var byPitch: [Int: [NoteEventWithTime]] = [:]
        for event in events {
            byPitch[event.midiPitch, default: []].append(event)
        }

        var allTracks = [[MIDIEvent]]()

        // First track: tempo only
        var tempoTrack = [MIDIEvent]()
        tempoTrack.append(.tempo(bpm: midiTempo, tick: 0))
        tempoTrack.append(.endOfTrack(tick: 0))
        allTracks.append(tempoTrack)

        // One track per pitch
        for (pitch, pitchEvents) in byPitch.sorted(by: { $0.key < $1.key }) {
            var trackEvents = [MIDIEvent]()
            let channel: UInt8 = 0
            trackEvents.append(.programChange(channel: channel, program: electricPiano1Program, tick: 0))

            for event in pitchEvents {
                let startTick = UInt32(round(event.startTime * ticksPerSecond))
                let endTick = UInt32(round(event.endTime * ticksPerSecond))
                let velocity = UInt8(min(127, max(0, Int(round(Float(Constants.midiVelocityScale) * event.amplitude)))))

                trackEvents.append(.noteOn(channel: channel, pitch: UInt8(clamping: pitch), velocity: velocity, tick: startTick))

                if let bends = event.pitchBends, !bends.isEmpty {
                    let bendTimes = linspace(start: event.startTime, end: event.endTime, count: bends.count)
                    for (i, bend) in bends.enumerated() {
                        var midiTicks = Int(round(Double(bend) * Constants.pitchBendScale / Double(Constants.contoursBinsPerSemitone)))
                        midiTicks = max(-Constants.nPitchBendTicks, min(Constants.nPitchBendTicks - 1, midiTicks))
                        let bendTick = UInt32(round(bendTimes[i] * ticksPerSecond))
                        trackEvents.append(.pitchBend(channel: channel, value: Int16(midiTicks), tick: bendTick))
                    }
                }

                trackEvents.append(.noteOff(channel: channel, pitch: UInt8(clamping: pitch), tick: endTick))
            }

            let lastTick = trackEvents.max(by: { $0.tick < $1.tick })?.tick ?? 0
            trackEvents.append(.endOfTrack(tick: lastTick))
            allTracks.append(trackEvents)
        }

        return buildSMF(format: 1, tracks: allTracks)
    }

    // MARK: - SMF binary encoding

    private enum MIDIEvent {
        case trackName(name: String, tick: UInt32)
        case tempo(bpm: Float, tick: UInt32)
        case programChange(channel: UInt8, program: UInt8, tick: UInt32)
        case noteOn(channel: UInt8, pitch: UInt8, velocity: UInt8, tick: UInt32)
        case noteOff(channel: UInt8, pitch: UInt8, tick: UInt32)
        case pitchBend(channel: UInt8, value: Int16, tick: UInt32)
        case endOfTrack(tick: UInt32)

        var tick: UInt32 {
            switch self {
            case .trackName(_, let t), .tempo(_, let t), .programChange(_, _, let t),
                 .noteOn(_, _, _, let t), .noteOff(_, _, let t),
                 .pitchBend(_, _, let t), .endOfTrack(let t):
                return t
            }
        }
    }

    private static func buildSMF(format: UInt16, tracks: [[MIDIEvent]]) -> Data {
        var data = Data()

        // Header chunk: "MThd"
        data.append(contentsOf: [0x4D, 0x54, 0x68, 0x64]) // MThd
        data.append(contentsOf: uint32Bytes(6)) // header length
        data.append(contentsOf: uint16Bytes(format))
        data.append(contentsOf: uint16Bytes(UInt16(tracks.count)))
        data.append(contentsOf: uint16Bytes(ticksPerQuarterNote))

        for track in tracks {
            let trackData = encodeTrack(track)
            data.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // MTrk
            data.append(contentsOf: uint32Bytes(UInt32(trackData.count)))
            data.append(trackData)
        }

        return data
    }

    private static func encodeTrack(_ events: [MIDIEvent]) -> Data {
        // Sort events by tick, then by type priority (tempo first, end-of-track last)
        let sorted = events.sorted { a, b in
            if a.tick != b.tick { return a.tick < b.tick }
            return eventPriority(a) < eventPriority(b)
        }

        var data = Data()
        var lastTick: UInt32 = 0

        for event in sorted {
            let delta = event.tick >= lastTick ? event.tick - lastTick : 0
            data.append(contentsOf: variableLengthQuantity(delta))
            lastTick = event.tick

            switch event {
            case .trackName(let name, _):
                let bytes = Array(name.utf8)
                data.append(contentsOf: [0xFF, 0x03])
                data.append(contentsOf: variableLengthQuantity(UInt32(bytes.count)))
                data.append(contentsOf: bytes)

            case .tempo(let bpm, _):
                let uspqn = UInt32(round(60_000_000.0 / Double(bpm)))
                data.append(contentsOf: [0xFF, 0x51, 0x03])
                data.append(UInt8((uspqn >> 16) & 0xFF))
                data.append(UInt8((uspqn >> 8) & 0xFF))
                data.append(UInt8(uspqn & 0xFF))

            case .programChange(let ch, let prog, _):
                data.append(0xC0 | (ch & 0x0F))
                data.append(prog & 0x7F)

            case .noteOn(let ch, let pitch, let vel, _):
                data.append(0x90 | (ch & 0x0F))
                data.append(pitch & 0x7F)
                data.append(vel & 0x7F)

            case .noteOff(let ch, let pitch, _):
                data.append(0x80 | (ch & 0x0F))
                data.append(pitch & 0x7F)
                data.append(0x00) // velocity 0

            case .pitchBend(let ch, let value, _):
                // MIDI pitch bend: center = 8192 (0x2000), range 0-16383
                let centered = Int(value) + 8192
                let clamped = max(0, min(16383, centered))
                let lsb = UInt8(clamped & 0x7F)
                let msb = UInt8((clamped >> 7) & 0x7F)
                data.append(0xE0 | (ch & 0x0F))
                data.append(lsb)
                data.append(msb)

            case .endOfTrack:
                data.append(contentsOf: [0xFF, 0x2F, 0x00])
            }
        }

        return data
    }

    private static func eventPriority(_ event: MIDIEvent) -> Int {
        switch event {
        case .trackName: return -1
        case .tempo: return 0
        case .programChange: return 1
        case .noteOff: return 2
        case .pitchBend: return 3
        case .noteOn: return 4
        case .endOfTrack: return 99
        }
    }

    private static func variableLengthQuantity(_ value: UInt32) -> [UInt8] {
        if value == 0 { return [0x00] }
        var val = value
        var bytes = [UInt8]()
        bytes.append(UInt8(val & 0x7F))
        val >>= 7
        while val > 0 {
            bytes.append(UInt8((val & 0x7F) | 0x80))
            val >>= 7
        }
        return bytes.reversed()
    }

    private static func uint32Bytes(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
         UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func uint16Bytes(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func linspace(start: Double, end: Double, count: Int) -> [Double] {
        guard count > 1 else { return [start] }
        let step = (end - start) / Double(count - 1)
        return (0..<count).map { start + Double($0) * step }
    }
}
