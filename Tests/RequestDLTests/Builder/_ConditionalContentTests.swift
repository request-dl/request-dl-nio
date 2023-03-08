//
//  _ConditionalContentTests.swift
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

final class _ConditionalContentTests: XCTestCase {

    func testConditionalFirstBuilder() async {
        // Given
        let chooseFirst = true

        @PropertyBuilder
        var result: some Property {
            if chooseFirst {
                BaseURL("google.com")
            } else {
                Headers.Origin("https://apple.com")
            }
        }

        // When
        let (_, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _ConditionalContent<BaseURL, Headers.Origin>)
        XCTAssertEqual(request.url?.absoluteString, "https://google.com")
        XCTAssertNil(request.allHTTPHeaderFields)
    }

    func testConditionalSecondBuilder() async {
        // Given
        let chooseFirst = false

        @PropertyBuilder
        var result: some Property {
            if chooseFirst {
                Headers.Origin("https://apple.com")
            } else {
                BaseURL("localhost")
            }
        }

        // When
        let (_, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _ConditionalContent<Headers.Origin, BaseURL>)
        XCTAssertEqual(request.url?.absoluteString, "https://localhost")
        XCTAssertNil(request.allHTTPHeaderFields)
    }

    func testNeverBody() async throws {
        // Given
        let type = _ConditionalContent<EmptyProperty, EmptyProperty>.self

        // Then
        XCTAssertTrue(type.Body.self == Never.self)
    }
}
