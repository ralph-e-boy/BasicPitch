#!/usr/bin/env python3
"""Compare Python basic-pitch output with Swift output on the same audio file.
Usage: python3 compare.py <audio_file>

Dumps intermediate values so you can spot where they diverge.
"""
import sys
import numpy as np
import librosa

sys.path.insert(0, ".")
from basic_pitch.inference import run_inference, Model, ICASSP_2022_MODEL_PATH, DEFAULT_OVERLAPPING_FRAMES
from basic_pitch.constants import AUDIO_SAMPLE_RATE, AUDIO_N_SAMPLES, FFT_HOP
from basic_pitch import note_creation as infer

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 compare.py <audio_file>")
        sys.exit(1)

    audio_path = sys.argv[1]

    # 1. Load audio the way basic-pitch does
    audio, _ = librosa.load(audio_path, sr=AUDIO_SAMPLE_RATE, mono=True)
    print(f"Audio: {len(audio)} samples, range [{audio.min():.4f}, {audio.max():.4f}]")

    # Save raw audio for Swift comparison
    np.save("/tmp/bp_python_audio.npy", audio)

    # 2. Run inference
    model_output = run_inference(audio_path, ICASSP_2022_MODEL_PATH)

    for key in ["note", "onset", "contour"]:
        arr = model_output[key]
        print(f"  {key}: shape={arr.shape}, range=[{arr.min():.4f}, {arr.max():.4f}], mean={arr.mean():.4f}")
        np.save(f"/tmp/bp_python_{key}.npy", arr)

    # 3. Run note detection
    min_note_len = int(np.round(127.7 / 1000 * (AUDIO_SAMPLE_RATE / FFT_HOP)))
    estimated_notes = infer.output_to_notes_polyphonic(
        model_output["note"],
        model_output["onset"],
        onset_thresh=0.5,
        frame_thresh=0.3,
        infer_onsets=True,
        min_note_len=min_note_len,
        min_freq=None,
        max_freq=None,
        melodia_trick=True,
    )

    print(f"\nNotes: {len(estimated_notes)}")
    if estimated_notes:
        pitches = [n[2] for n in estimated_notes]
        print(f"  Pitch range: MIDI {min(pitches)} - {max(pitches)}")
        # Show distribution
        for bucket_start in range(21, 109, 12):
            bucket_end = bucket_start + 12
            count = sum(1 for p in pitches if bucket_start <= p < bucket_end)
            if count > 0:
                note_name = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
                octave = (bucket_start - 12) // 12
                print(f"    MIDI {bucket_start:3d}-{bucket_end-1:3d} ({note_name[bucket_start%12]}{octave}-{note_name[(bucket_end-1)%12]}{octave}): {count} notes")

if __name__ == "__main__":
    main()
