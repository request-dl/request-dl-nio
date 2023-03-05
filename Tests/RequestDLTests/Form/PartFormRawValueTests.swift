//
//  PartFormRawValue.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import XCTest
@testable import RequestDL

final class PartFormRawValueTests: XCTestCase {

    func testInitWithDataAndHeaders() throws {
        // Given
        let data = "Test data".data(using: .utf8)!
        let headers: [String: Any] = [
            "Content-Type": "text/plain",
            "Content-Length": 9,
            "Custom-Header": "custom-value"
        ]

        // When
        let part = PartFormRawValue(data, forHeaders: headers)

        // Then
        XCTAssertEqual(part.data, data)
        XCTAssertEqual(part.headers.count, 3)
        XCTAssertEqual(part.headers["Content-Type"] as? String, "text/plain")
        XCTAssertEqual(part.headers["Content-Length"] as? Int, 9)
        XCTAssertEqual(part.headers["Custom-Header"] as? String, "custom-value")
    }

    func testContentDispositionValue_withFileName() {
        // Given
        let key = "testKey"
        let fileName = "testFile.txt"

        // When
        let contentDisposition = kContentDispositionValue(fileName, forKey: key)

        // Then
        XCTAssertEqual(
            contentDisposition,
            "form-data; name=\"\(key)\"; filename=\"\(fileName)\""
        )
    }

    func testContentDispositionValue_withoutFileName() {
        // Given
        let key = "testKey"

        // When
        let contentDisposition = kContentDispositionValue(nil, forKey: key)

        // Then
        XCTAssertEqual(contentDisposition, "form-data; name=\"\(key)\"")
    }
}
