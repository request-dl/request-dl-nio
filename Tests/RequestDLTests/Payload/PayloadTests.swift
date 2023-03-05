//
//  PayloadTests.swift
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

final class PayloadTests: XCTestCase {

    struct Mock: Codable {
        let foo: String
        let date: Date
    }

    func testDictionaryPayload() async throws {
        // Given
        let dictionary: [String: Any] = [
            "foo": "bar",
            "number": 123
        ]

        let options = JSONSerialization.WritingOptions([.withoutEscapingSlashes])

        // When
        let property = TestProperty(Payload(dictionary, options: options))
        let (_, request) = await resolve(property)
        let expectedPayload = _DictionaryPayload(dictionary, options: options)

        // Then
        XCTAssertEqual(request.httpBody, expectedPayload.data)
    }

    func testStringPayload() async throws {
        // Given
        let foo = "foo"
        let encoding = String.Encoding.utf8

        // When
        let property = TestProperty(Payload(foo, using: encoding))
        let (_, request) = await resolve(property)
        let expectedPayload = _StringPayload(foo, using: encoding)

        // Then
        XCTAssertEqual(request.httpBody, expectedPayload.data)
    }

    func testDataPayload() async throws {
        // Given
        let data = Data("foo,bar".utf8)

        // When
        let property = TestProperty(Payload(data))
        let (_, request) = await resolve(property)
        let expectedPayload = _DataPayload(data)

        // Then
        XCTAssertEqual(request.httpBody, expectedPayload.data)
    }

    func testEncodablePayload() async throws {
        // Given
        let mock = Mock(
            foo: "foo",
            date: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        // When
        let property = TestProperty(Payload(mock, encoder: encoder))
        let (_, request) = await resolve(property)
        let expectedPayload = _EncodablePayload(mock, encoder: encoder)
        let expectedMock = try decoder.decode(Mock.self, from: expectedPayload.data)

        // Then
        XCTAssertEqual(request.httpBody, expectedPayload.data)
        XCTAssertEqual(mock.foo, expectedMock.foo)

        XCTAssertEqual(
            mock.date.timeIntervalSince1970,
            expectedMock.date.timeIntervalSince1970
        )
    }
}
