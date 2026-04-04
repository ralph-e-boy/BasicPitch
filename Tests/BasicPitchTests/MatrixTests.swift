// Copyright 2024 Spotify AB
// Licensed under the Apache License, Version 2.0

import XCTest
@testable import BasicPitch

final class MatrixTests: XCTestCase {
    func testSubscript() {
        var m = Matrix(rows: 2, cols: 3, data: [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(m[0, 0], 1)
        XCTAssertEqual(m[0, 2], 3)
        XCTAssertEqual(m[1, 1], 5)
        m[1, 2] = 99
        XCTAssertEqual(m[1, 2], 99)
    }

    func testMaxAndArgmax() {
        let m = Matrix(rows: 2, cols: 3, data: [1, 2, 3, 4, 9, 6])
        XCTAssertEqual(m.maxValue(), 9)
        let (r, c) = m.argmax()
        XCTAssertEqual(r, 1)
        XCTAssertEqual(c, 1)
    }

    func testSubmatrix() {
        let m = Matrix(rows: 3, cols: 4, data: Array(1...12).map { Float($0) })
        let sub = m.submatrix(rowRange: 1..<3, colRange: 1..<3)
        XCTAssertEqual(sub.rows, 2)
        XCTAssertEqual(sub.cols, 2)
        XCTAssertEqual(sub[0, 0], 6)  // row 1, col 1 of original
        XCTAssertEqual(sub[1, 1], 11) // row 2, col 2 of original
    }

    func testArgmaxPerRow() {
        let m = Matrix(rows: 2, cols: 3, data: [1, 5, 2, 8, 3, 4])
        let result = m.argmaxPerRow()
        XCTAssertEqual(result, [1, 0])
    }

    func testZeroOutColumns() {
        var m = Matrix(rows: 2, cols: 4, data: [1, 2, 3, 4, 5, 6, 7, 8])
        m.zeroOutColumns(below: 1, above: 3)
        // cols 0 should be zeroed, cols 3 should be zeroed
        XCTAssertEqual(m[0, 0], 0)
        XCTAssertEqual(m[0, 1], 2)
        XCTAssertEqual(m[0, 2], 3)
        XCTAssertEqual(m[0, 3], 0)
    }
}
