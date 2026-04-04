#!/usr/bin/env python3
"""Compare two MIDI files note by note."""
import sys
import pretty_midi

def analyze(path, label):
    mid = pretty_midi.PrettyMIDI(path)
    notes = []
    for inst in mid.instruments:
        for n in inst.notes:
            notes.append(n)
    notes.sort(key=lambda n: n.start)
    pitches = [n.pitch for n in notes]
    print(f"\n{label}: {path}")
    print(f"  Notes: {len(notes)}")
    if not notes:
        return notes
    print(f"  Pitch range: MIDI {min(pitches)} – {max(pitches)}")
    note_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    for octave in range(0, 9):
        lo = 12 + octave * 12
        hi = lo + 11
        count = sum(1 for p in pitches if lo <= p <= hi)
        if count > 0:
            print(f"    {note_names[0]}{octave}–{note_names[11]}{octave} (MIDI {lo:3d}–{hi:3d}): {count:4d} notes")

    # Show first 15 seconds
    print(f"  First 15 seconds:")
    for n in notes:
        if n.start > 15:
            break
        name = note_names[n.pitch % 12] + str(n.pitch // 12 - 1)
        print(f"    {n.start:6.2f}s  {name:4s} (MIDI {n.pitch:3d})  dur={n.end-n.start:.2f}s  vel={n.velocity}")
    return notes

python_notes = analyze("/tmp/python_out/sample_basic_pitch.mid", "PYTHON")
swift_notes = analyze("/tmp/swift_sample.mid", "SWIFT")
