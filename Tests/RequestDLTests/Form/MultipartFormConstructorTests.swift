//
//  MultipartFormConstructorTests.swift
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

final class MultipartFormConstructorTests: XCTestCase {

    func testSingleMultipartConstructor() async throws {
        // Given
        let value = "foo"
        let form = PartFormRawValue(Data(value.utf8), forHeaders: [
            "Content-Disposition": "form-data; name=\"string\""
        ])

        // When
        let constructor = MultipartFormConstructor([form])

        let multipartForm = try MultipartFormParser(
            constructor.body,
            boundary: constructor.boundary
        ).parse()

        // Then
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"string\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testMultipleMultipartConstructor() async throws {
        // Given
        let value1 = "foo"
        let form1 = PartFormRawValue(Data(value1.utf8), forHeaders: [
            "Content-Disposition": "form-data; name=\"string\""
        ])

        let value2 = CharacterSet.alphanumerics.description
        let form2 = PartFormRawValue(Data(value2.utf8), forHeaders: [
            "Content-Disposition": "form-data; name=\"document\"; filename=\"document.pdf\"",
            "Content-Type": ContentType.pdf
        ])

        // When
        let constructor = MultipartFormConstructor([form1, form2])

        let multipartForm = try MultipartFormParser(
            constructor.body,
            boundary: constructor.boundary
        ).parse()

        // Then
        XCTAssertEqual(multipartForm.items.count, 2)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"string\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value1.utf8))

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Disposition"],
            "form-data; name=\"document\"; filename=\"document.pdf\""
        )

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Type"],
            "application/pdf"
        )

        XCTAssertEqual(multipartForm.items[1].contents, Data(value2.utf8))
    }
}
