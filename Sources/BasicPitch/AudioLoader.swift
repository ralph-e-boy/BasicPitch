// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import AVFoundation
import Foundation

public enum AudioLoader {
    /// Resample raw audio samples to 22050 Hz mono Float32.
    /// Uses maximum quality AVAudioConverter resampling (Kaiser-windowed sinc).
    /// Input is channel-interleaved or single-channel `[Float]`.
    public static func resampleToMono(_ samples: [Float], channels: Int, sampleRate: Int) throws -> [Float] {
        guard channels > 0, sampleRate > 0, !samples.isEmpty else {
            throw BasicPitchError.audioConversionFailed("Invalid audio: channels=\(channels), sampleRate=\(sampleRate), samples=\(samples.count)")
        }
        let frameCount = samples.count / channels

        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Constants.audioSampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw BasicPitchError.invalidAudioFormat("Cannot create target audio format")
        }

        // If already at target rate and mono, return as-is
        if channels == 1 && sampleRate == Constants.audioSampleRate {
            return samples
        }

        // Mix to mono first if multi-channel (channel-major layout: [ch0_samples..., ch1_samples...])
        let monoSamples: [Float]
        if channels == 1 {
            monoSamples = samples
        } else {
            monoSamples = [Float](unsafeUninitializedCapacity: frameCount) { buffer, count in
                let scale = 1.0 / Float(channels)
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for ch in 0..<channels {
                        sum += samples[ch * frameCount + i]
                    }
                    buffer[i] = sum * scale
                }
                count = frameCount
            }
        }

        // If already at target rate after mono mix, return
        if sampleRate == Constants.audioSampleRate {
            return monoSamples
        }

        // Resample mono to target rate
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw BasicPitchError.invalidAudioFormat("Cannot create mono source format")
        }

        guard let converter = AVAudioConverter(from: monoFormat, to: dstFormat) else {
            throw BasicPitchError.audioConversionFailed(
                "Cannot create converter from \(sampleRate)Hz to \(Constants.audioSampleRate)Hz"
            )
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal

        let estimatedOutputFrames = AVAudioFrameCount(
            ceil(Double(frameCount) * Double(Constants.audioSampleRate) / Double(sampleRate))
        )

        guard let srcBuffer = AVAudioPCMBuffer(
            pcmFormat: monoFormat,
            frameCapacity: AVAudioFrameCount(monoSamples.count)
        ) else {
            throw BasicPitchError.audioConversionFailed("Cannot create source buffer")
        }
        srcBuffer.frameLength = AVAudioFrameCount(monoSamples.count)
        memcpy(srcBuffer.floatChannelData![0], monoSamples, monoSamples.count * MemoryLayout<Float>.size)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: dstFormat,
            frameCapacity: estimatedOutputFrames + 4096
        ) else {
            throw BasicPitchError.audioConversionFailed("Cannot create output buffer")
        }

        let sliceCapacity: AVAudioFrameCount = 16384
        guard let sliceBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: sliceCapacity) else {
            throw BasicPitchError.audioConversionFailed("Cannot create slice buffer")
        }

        var srcOffset: AVAudioFramePosition = 0
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if srcOffset >= Int64(srcBuffer.frameLength) {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            let framesRemaining = AVAudioFrameCount(Int64(srcBuffer.frameLength) - srcOffset)
            let framesToCopy = min(framesRemaining, sliceCapacity)
            sliceBuffer.frameLength = framesToCopy
            memcpy(sliceBuffer.floatChannelData![0],
                   srcBuffer.floatChannelData![0].advanced(by: Int(srcOffset)),
                   Int(framesToCopy) * MemoryLayout<Float>.size)
            srcOffset += Int64(framesToCopy)
            return sliceBuffer
        }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        if status == .error, let err = conversionError {
            throw BasicPitchError.audioConversionFailed(err.localizedDescription)
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw BasicPitchError.audioConversionFailed("No float channel data in output")
        }
        let outFrameCount = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: outFrameCount))
    }

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
        let sliceCapacity: AVAudioFrameCount = 16384
        guard let sliceBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: sliceCapacity) else {
            throw BasicPitchError.audioConversionFailed("Cannot create slice buffer")
        }
        let channelCount = Int(srcFormat.channelCount)

        var srcOffset: AVAudioFramePosition = 0
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if srcOffset >= Int64(srcBuffer.frameLength) {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            let framesRemaining = AVAudioFrameCount(Int64(srcBuffer.frameLength) - srcOffset)
            let framesToCopy = min(framesRemaining, sliceCapacity)
            sliceBuffer.frameLength = framesToCopy

            for ch in 0..<channelCount {
                memcpy(sliceBuffer.floatChannelData![ch],
                       srcBuffer.floatChannelData![ch].advanced(by: Int(srcOffset)),
                       Int(framesToCopy) * MemoryLayout<Float>.size)
            }
            srcOffset += Int64(framesToCopy)
            return sliceBuffer
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
