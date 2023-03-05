//
//  HeaderGroupTests.swift
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

final class HeaderGroupTests: XCTestCase {

    func testHeaderGroupWithEmptyValue() async throws {
        let property = TestProperty(HeaderGroup {})
        let (_, request) = await resolve(property)
        XCTAssertTrue(request.allHTTPHeaderFields?.isEmpty ?? true)
    }

    func testHeaderGroupWithDictionary() async throws {
        let property = TestProperty(HeaderGroup([
            "Content-Type": "application/json",
            "Accept": "text/html",
            "Origin": "localhost:8080",
            "xxx-api-key": "password"
        ]))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/html")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "localhost:8080")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password")
    }

    func testHeaderGroupWithMultipleHeaders() async throws {
        let property = TestProperty(HeaderGroup {
            Headers.ContentType(.javascript)
            Headers.Accept(.json)
            Headers.Origin("localhost:8080")
            Headers.Any("password", forKey: "xxx-api-key")
        })

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/javascript")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "localhost:8080")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password")
    }
}
