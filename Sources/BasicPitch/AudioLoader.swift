// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import AVFoundation
import Foundation

public enum AudioLoader {
    /// Load an audio file, resample to 22050 Hz mono Float32.
    /// Uses maximum quality resampling to match librosa's Kaiser-windowed sinc.
    public static func loadAudio(from url: URL) throws -> [Float] {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw BasicPitchError.audioLoadFailed(url, error)
        }

        // Read in the file's native processing format (always float32 PCM)
        let srcFormat = audioFile.processingFormat

        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Constants.audioSampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw BasicPitchError.invalidAudioFormat("Cannot create target audio format")
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw BasicPitchError.audioConversionFailed(
                "Cannot create converter from \(srcFormat) to \(dstFormat)"
            )
        }

        // Use highest quality resampling — this matches librosa's resampy (Kaiser best)
        // and preserves high-frequency content that the model needs.
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal

        // Calculate output capacity
        let srcSampleRate = srcFormat.sampleRate
        let dstSampleRate = dstFormat.sampleRate
        let estimatedOutputFrames = AVAudioFrameCount(
            ceil(Double(audioFile.length) * dstSampleRate / srcSampleRate)
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: dstFormat,
            frameCapacity: estimatedOutputFrames + 4096
        ) else {
            throw BasicPitchError.audioConversionFailed("Cannot create output buffer")
        }

        // Read entire source file
        guard let srcBuffer = AVAudioPCMBuffer(
            pcmFormat: srcFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        ) else {
            throw BasicPitchError.audioConversionFailed("Cannot create source buffer")
        }
        do {
            try audioFile.read(into: srcBuffer)
        } catch {
            throw BasicPitchError.audioLoadFailed(url, error)
        }

        // Convert in one pass via input block
        var srcOffset: AVAudioFramePosition = 0
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if srcOffset >= Int64(srcBuffer.frameLength) {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            let framesRemaining = AVAudioFrameCount(Int64(srcBuffer.frameLength) - srcOffset)
            let framesToCopy = min(framesRemaining, 16384)
            guard let slice = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: framesToCopy) else {
                outStatus.pointee = .endOfStream
                return nil
            }
            slice.frameLength = framesToCopy

            let channelCount = Int(srcFormat.channelCount)
            for ch in 0..<channelCount {
                memcpy(slice.floatChannelData![ch],
                       srcBuffer.floatChannelData![ch].advanced(by: Int(srcOffset)),
                       Int(framesToCopy) * MemoryLayout<Float>.size)
            }
            srcOffset += Int64(framesToCopy)
            return slice
        }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        if status == .error, let err = conversionError {
            throw BasicPitchError.audioConversionFailed(err.localizedDescription)
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw BasicPitchError.audioConversionFailed("No float channel data in output")
        }

        let frameCount = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameCount))
    }
}
