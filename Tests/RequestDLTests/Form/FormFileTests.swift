//
//  FormFile.swift
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

final class FormFileTests: XCTestCase {

    func testFileFormWithFileNameAndContentType() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        let property = FormFile(
            url,
            forKey: "document",
            fileName: "file.pdf",
            type: .pdf
        )

        // When
        let (_, request) = await resolve(TestProperty(property))

        let contentTypeHeader = request.value(forHTTPHeaderField: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            request.httpBody ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(property.key)\"; filename=\"\(property.fileName)\""
        )

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Type"],
            property.contentType.rawValue
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testEmptyFileName() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        let property = FormFile(
            url,
            forKey: "document",
            fileName: "",
            type: .pdf
        )

        // When
        let (_, request) = await resolve(TestProperty(property))

        let contentTypeHeader = request.value(forHTTPHeaderField: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            request.httpBody ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(property.key)\"; filename=\"\""
        )

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Type"],
            property.contentType.rawValue
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testFileNameResolver() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        // When
        let fileName = FormFile(
            url,
            forKey: "document",
            fileName: nil,
            type: .pdf
        ).fileName

        // Then
        XCTAssertEqual(fileName, "bar.pdf")
    }

    func testContentTypeResolver() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        // When
        let contentType = FormFile(
            url,
            forKey: "document",
            fileName: nil,
            type: nil
        ).contentType

        // Then
        XCTAssertEqual(contentType, .pdf)
    }

    func testOctetStreamResolved() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")

        try Data(value.utf8).write(to: url)

        // When
        let contentType = FormFile(
            url,
            forKey: "document",
            fileName: nil,
            type: nil
        ).contentType

        // Then
        XCTAssertEqual(contentType, "application/octet-stream")
    }

    func testNeverBody() async throws {
        // Given
        let type = FormFile.self

        // Then
        XCTAssertTrue(type.Body.self == Never.self)
    }
}
