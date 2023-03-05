//
//  FormData.swift
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

final class FormDataTests: XCTestCase {

    struct Mock: Codable {
        let foo: String
        let date: Date
    }

    func testDataFormWithFileName() async throws {
        // Given
        let value = "foo"

        let property = FormData(
            Data(value.utf8),
            forKey: "raw_string",
            fileName: "data.txt",
            type: .text
        )

        // When
        let (_, request) = await resolve(TestProperty(property))
        let contentTypeHeader = request.value(forHTTPHeaderField: "Content-Type")
        let boundary = ReverseFormData.extractBoundary(contentTypeHeader) ?? "nil"
        let reversed = ReverseFormData(request.httpBody ?? Data(), boundary: boundary)

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(reversed.items.count, 1)

        XCTAssertEqual(
            reversed.items[0].headers?["Content-Disposition"],
            "form-data; name=\"\(property.key)\"; filename=\"\(property.fileName)\""
        )

        XCTAssertEqual(
            reversed.items[0].headers?["Content-Type"],
            property.contentType.rawValue
        )

        XCTAssertEqual(reversed.items[0].data, value)
    }

    func testDataFormWithoutFileName() async throws {
        // Given
        let value = "foo"

        let property = FormData(
            Data(value.utf8),
            forKey: "raw_string",
            type: .text
        )

        // When
        let (_, request) = await resolve(TestProperty(property))
        let contentTypeHeader = request.value(forHTTPHeaderField: "Content-Type")
        let boundary = ReverseFormData.extractBoundary(contentTypeHeader) ?? "nil"
        let reversed = ReverseFormData(request.httpBody ?? Data(), boundary: boundary)

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(reversed.items.count, 1)

        XCTAssertEqual(
            reversed.items[0].headers?["Content-Disposition"],
            "form-data; name=\"\(property.key)\"; filename=\"\""
        )

        XCTAssertEqual(
            reversed.items[0].headers?["Content-Type"],
            property.contentType.rawValue
        )

        XCTAssertEqual(reversed.items[0].data, value)
    }

    func testEncodableData() async throws {
        // Given
        let mock = Mock(
            foo: "bar",
            date: Date()
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970

        // When
        let property = FormData(
            mock,
            forKey: "data",
            encoder: encoder
        )

        let expectedData = try encoder.encode(mock)
        let expectedMock = try decoder.decode(Mock.self, from: property.data)

        // Then
        XCTAssertEqual(property.contentType, .json)
        XCTAssertEqual(property.fileName, "")
        XCTAssertEqual(property.key, "data")
        XCTAssertEqual(property.data, expectedData)
        XCTAssertEqual(expectedMock.foo, mock.foo)
        XCTAssertEqual(expectedMock.date.timeIntervalSince1970, mock.date.timeIntervalSince1970)
    }

    func testEncodableWithFilename() async throws {
        // Given
        let fileName = "contents.json"

        // When
        let property = FormData(
            Mock(foo: "bar", date: Date()),
            forKey: "data",
            fileName: fileName
        )

        // Then
        XCTAssertEqual(property.fileName, fileName)
    }
}
