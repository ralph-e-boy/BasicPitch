// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import Foundation

public enum BasicPitchError: Error, LocalizedError {
    case audioLoadFailed(URL, Error)
    case audioConversionFailed(String)
    case modelLoadFailed(Error)
    case modelNotFound
    case inferenceError(Error)
    case invalidAudioFormat(String)
    case midiWriteFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .audioLoadFailed(let url, let err):
            return "Failed to load audio from \(url): \(err.localizedDescription)"
        case .audioConversionFailed(let msg):
            return "Audio conversion failed: \(msg)"
        case .modelLoadFailed(let err):
            return "Failed to load CoreML model: \(err.localizedDescription)"
        case .modelNotFound:
            return "CoreML model not found in bundle"
        case .inferenceError(let err):
            return "Model inference failed: \(err.localizedDescription)"
        case .invalidAudioFormat(let msg):
            return "Invalid audio format: \(msg)"
        case .midiWriteFailed(let err):
            return "Failed to write MIDI file: \(err.localizedDescription)"
        }
    }
}
