// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import Accelerate
import CoreML
import Foundation

public struct WindowPrediction: Sendable {
    public let notes: Matrix   // 172 x 88
    public let onsets: Matrix   // 172 x 88
    public let contours: Matrix // 172 x 264
}

public final class CoreMLInference: @unchecked Sendable {
    private let model: MLModel
    private var modelURL: URL
    private let config: MLModelConfiguration

    public init(modelURL: URL, configuration: MLModelConfiguration? = nil) throws {
        let config = configuration ?? {
            let c = MLModelConfiguration()
            c.computeUnits = .cpuAndNeuralEngine
            return c
        }()
        self.config = config
        self.modelURL = modelURL
        do {
            self.model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            do {
                let compiledURL = try MLModel.compileModel(at: modelURL)
                self.model = try MLModel(contentsOf: compiledURL, configuration: config)
                self.modelURL = compiledURL
            } catch let compileError {
                throw BasicPitchError.modelLoadFailed(compileError)
            }
        }
    }

    /// Load model from the SPM bundle resource.
    public convenience init(configuration: MLModelConfiguration? = nil) throws {
        if let compiledURL = Bundle.module.url(forResource: "nmp", withExtension: "mlmodelc") {
            try self.init(modelURL: compiledURL, configuration: configuration)
            return
        }
        if let packageURL = Bundle.module.url(forResource: "nmp", withExtension: "mlpackage") {
            try self.init(modelURL: packageURL, configuration: configuration)
            return
        }
        throw BasicPitchError.modelNotFound
    }

    // MARK: - Single prediction

    /// Run inference on a single audio window (43844 floats).
    public func predict(window: [Float]) throws -> WindowPrediction {
        let result = try runModel(model, window: window)
        return try extractPrediction(from: result)
    }

    // MARK: - Batch parallel prediction

    /// Run inference on all windows concurrently using multiple model instances.
    /// CoreML's Neural Engine can pipeline work, and multiple MLModel copies
    /// allow true concurrent dispatch.
    public func predictBatch(
        windows: [[Float]],
        concurrency: Int = ProcessInfo.processInfo.activeProcessorCount,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) throws -> [WindowPrediction] {
        let count = windows.count
        guard count > 0 else { return [] }

        // For small batches, run serially — threading overhead isn't worth it
        if count <= 2 {
            return try windows.enumerated().map { i, w in
                progressHandler?(i, count)
                return try predict(window: w)
            }
        }

        // Load additional model copies for parallel execution
        let nWorkers = min(concurrency, count)
        var models = [model]
        for _ in 1..<nWorkers {
            if let m = try? MLModel(contentsOf: modelURL, configuration: config) {
                models.append(m)
            }
        }

        // Results array and error tracking
        let results = UnsafeMutableBufferPointer<WindowPrediction?>.allocate(capacity: count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }

        var firstError: Error?
        let errorLock = NSLock()
        let progressLock = NSLock()
        var completed = 0

        DispatchQueue.concurrentPerform(iterations: count) { i in
            // Check if we already have an error
            errorLock.lock()
            let hasError = firstError != nil
            errorLock.unlock()
            guard !hasError else { return }

            let workerModel = models[i % models.count]
            do {
                let result = try runModel(workerModel, window: windows[i])
                let pred = try extractPrediction(from: result)
                results[i] = pred

                if let progress = progressHandler {
                    progressLock.lock()
                    completed += 1
                    let c = completed
                    progressLock.unlock()
                    progress(c, count)
                }
            } catch {
                errorLock.lock()
                if firstError == nil { firstError = error }
                errorLock.unlock()
            }
        }

        if let error = firstError { throw error }
        return (0..<count).map { results[$0]! }
    }

    // MARK: - Internals

    /// Reusable MLMultiArray input — allocated once per call to avoid repeated allocation.
    private func runModel(_ model: MLModel, window: [Float]) throws -> MLFeatureProvider {
        let audioNSamples = Constants.audioNSamples
        let inputArray = try MLMultiArray(shape: [1, NSNumber(value: audioNSamples), 1], dataType: .float32)
        let ptr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: audioNSamples)

        window.withUnsafeBufferPointer { src in
            let copyCount = min(src.count, audioNSamples)
            memcpy(ptr, src.baseAddress!, copyCount * MemoryLayout<Float>.size)
            if copyCount < audioNSamples {
                memset(ptr.advanced(by: copyCount), 0, (audioNSamples - copyCount) * MemoryLayout<Float>.size)
            }
        }

        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["input_2": MLFeatureValue(multiArray: inputArray)]
        )
        do {
            return try model.prediction(from: provider)
        } catch {
            throw BasicPitchError.inferenceError(error)
        }
    }

    private func extractPrediction(from result: MLFeatureProvider) throws -> WindowPrediction {
        let notes = try extractMatrix(from: result, key: "Identity_1",
                                      rows: Constants.annotNFrames, cols: Constants.nFreqBinsNotes)
        let onsets = try extractMatrix(from: result, key: "Identity_2",
                                       rows: Constants.annotNFrames, cols: Constants.nFreqBinsNotes)
        let contours = try extractMatrix(from: result, key: "Identity",
                                          rows: Constants.annotNFrames, cols: Constants.nFreqBinsContours)
        return WindowPrediction(notes: notes, onsets: onsets, contours: contours)
    }

    private func extractMatrix(from result: MLFeatureProvider, key: String, rows: Int, cols: Int) throws -> Matrix {
        guard let multiArray = result.featureValue(for: key)?.multiArrayValue else {
            throw BasicPitchError.inferenceError(
                NSError(domain: "BasicPitch", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing output key: \(key)"])
            )
        }

        let strides = multiArray.strides.map { $0.intValue }
        let totalCount = rows * cols
        var data = [Float](repeating: 0, count: totalCount)
        let srcPtr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: strides[0])

        data.withUnsafeMutableBufferPointer { dst in
            if strides[2] == 1 {
                for r in 0..<rows {
                    memcpy(dst.baseAddress!.advanced(by: r * cols),
                           srcPtr.advanced(by: r * strides[1]),
                           cols * MemoryLayout<Float>.size)
                }
            } else {
                for r in 0..<rows {
                    cblas_scopy(Int32(cols),
                               srcPtr.advanced(by: r * strides[1]), Int32(strides[2]),
                               dst.baseAddress!.advanced(by: r * cols), 1)
                }
            }
        }
        return Matrix(rows: rows, cols: cols, data: data)
    }
}
