//
//  QueryTests.swift
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

final class QueryTests: XCTestCase {

    func testSingleQuery() async throws {
        // Given
        let property = Query(123, forKey: "number")

        // When
        let (_, request) = await resolve(TestProperty {
            BaseURL("localhost")
            property
        })

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://localhost?number=123")
    }

    func testMultipleQueries() async throws {
        // Given
        let property = TestProperty {
            BaseURL("localhost")
            Query(123, forKey: "number")
            Query(1, forKey: "page")
            Query("password", forKey: "api_key")
            Query([9, "nine"], forKey: "array")
        }

        // When
        let (_, request) = await resolve(property)

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            """
            https://localhost?\
            number=123&\
            page=1&\
            api_key=password&\
            array=%5B9,%20%22nine%22%5D
            """
        )
    }
}
