// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import Foundation
import Accelerate

public struct Matrix: Sendable {
    public var data: [Float]
    public let rows: Int
    public let cols: Int

    public init(rows: Int, cols: Int, data: [Float]) {
        precondition(data.count == rows * cols, "Data count \(data.count) != rows*cols \(rows*cols)")
        self.rows = rows
        self.cols = cols
        self.data = data
    }

    public init(rows: Int, cols: Int, repeating value: Float = 0) {
        self.rows = rows
        self.cols = cols
        self.data = [Float](repeating: value, count: rows * cols)
    }

    @inline(__always)
    public subscript(row: Int, col: Int) -> Float {
        get { data[row * cols + col] }
        set { data[row * cols + col] = newValue }
    }

    public func row(_ r: Int) -> ArraySlice<Float> {
        let start = r * cols
        return data[start..<(start + cols)]
    }

    public func submatrix(rowRange: Range<Int>, colRange: Range<Int>) -> Matrix {
        let newRows = rowRange.count
        let newCols = colRange.count
        var result = [Float](repeating: 0, count: newRows * newCols)
        result.withUnsafeMutableBufferPointer { dst in
            data.withUnsafeBufferPointer { src in
                for (ri, r) in rowRange.enumerated() {
                    let srcStart = src.baseAddress!.advanced(by: r * cols + colRange.lowerBound)
                    let dstStart = dst.baseAddress!.advanced(by: ri * newCols)
                    vDSP_mmov(srcStart, dstStart, vDSP_Length(newCols), vDSP_Length(1), 1, vDSP_Length(newCols))
                }
            }
        }
        return Matrix(rows: newRows, cols: newCols, data: result)
    }

    public func maxValue() -> Float {
        data.withUnsafeBufferPointer { buf in
            var result: Float = -.greatestFiniteMagnitude
            vDSP_maxv(buf.baseAddress!, 1, &result, vDSP_Length(buf.count))
            return result
        }
    }

    /// Find the (row, col) of the maximum element using vDSP.
    public func argmax() -> (row: Int, col: Int) {
        data.withUnsafeBufferPointer { buf in
            var maxVal: Float = 0
            var maxIdx: vDSP_Length = 0
            vDSP_maxvi(buf.baseAddress!, 1, &maxVal, &maxIdx, vDSP_Length(buf.count))
            let idx = Int(maxIdx)
            return (idx / cols, idx % cols)
        }
    }

    /// Find the argmax of each row using vDSP.
    public func argmaxPerRow() -> [Int] {
        data.withUnsafeBufferPointer { buf in
            (0..<rows).map { r in
                let start = r * cols
                var maxVal: Float = 0
                var maxIdx: vDSP_Length = 0
                vDSP_maxvi(buf.baseAddress!.advanced(by: start), 1, &maxVal, &maxIdx, vDSP_Length(cols))
                return Int(maxIdx)
            }
        }
    }

    public mutating func zeroOutColumns(below: Int, above: Int) {
        let belowClamped = min(below, cols)
        let aboveClamped = max(0, above)
        guard belowClamped > 0 || aboveClamped < cols else { return }
        data.withUnsafeMutableBufferPointer { buf in
            for r in 0..<rows {
                let rowStart = r * cols
                if belowClamped > 0 {
                    memset(buf.baseAddress!.advanced(by: rowStart), 0, belowClamped * MemoryLayout<Float>.size)
                }
                if aboveClamped < cols {
                    let count = cols - aboveClamped
                    memset(buf.baseAddress!.advanced(by: rowStart + aboveClamped), 0, count * MemoryLayout<Float>.size)
                }
            }
        }
    }

    public mutating func zeroOutRows(below: Int, above: Int) {
        data.withUnsafeMutableBufferPointer { buf in
            let endZero = min(below, rows) * cols
            if endZero > 0 {
                memset(buf.baseAddress!, 0, endZero * MemoryLayout<Float>.size)
            }
            let startAbove = max(0, above) * cols
            if startAbove < buf.count {
                memset(buf.baseAddress!.advanced(by: startAbove), 0, (buf.count - startAbove) * MemoryLayout<Float>.size)
            }
        }
    }

    /// Zero a column span across a row range using strided vDSP.
    public mutating func zeroColumn(_ col: Int, fromRow: Int, toRow: Int) {
        let count = toRow - fromRow
        guard count > 0 else { return }
        data.withUnsafeMutableBufferPointer { buf in
            vDSP_vclr(buf.baseAddress!.advanced(by: fromRow * cols + col),
                     vDSP_Stride(cols), vDSP_Length(count))
        }
    }

    /// Compute mean of a column across a row range using vDSP with stride.
    public func meanOfColumn(_ col: Int, fromRow: Int, toRow: Int) -> Float {
        let count = toRow - fromRow
        guard count > 0 else { return 0 }
        return data.withUnsafeBufferPointer { buf in
            var result: Float = 0
            // stride = cols (jump one row at a time in the same column)
            vDSP_meanv(buf.baseAddress!.advanced(by: fromRow * cols + col),
                       vDSP_Stride(cols), &result, vDSP_Length(count))
            return result
        }
    }
}
