//
//  QueryGroupTests.swift
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

final class QueryGroupTests: XCTestCase {

    func testGroupOfQueries() async throws {
        // Given
        let property = QueryGroup {
            Query(123, forKey: "number")
            Query(1, forKey: "page")
        }

        // When
        let (_, request) = await resolve(TestProperty {
            BaseURL("localhost")
            property
        })

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            """
            https://localhost?\
            number=123&\
            page=1
            """
        )
    }

    func testGroupOfQueriesIgnoringOtherTypes() async throws {
        // Given
        let property = QueryGroup {
            Query(123, forKey: "number")
            Query(1, forKey: "page")
            Headers.Any("password", forKey: "api_key")
        }

        // When
        let (_, request) = await resolve(TestProperty {
            BaseURL("localhost")
            property
        })

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            """
            https://localhost?\
            number=123&\
            page=1
            """
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "api_key"))
    }

    func testNeverBody() async throws {
        // Given
        let type = QueryGroup<EmptyProperty>.self

        // Then
        XCTAssertTrue(type.Body.self == Never.self)
    }
}
