//
//  HeadersTests.swift
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

final class HeadersTests: XCTestCase {

    func testMultipleHeadersWithoutGroup() async throws {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.Accept(.json)
            Headers.Origin("localhost:8080")
            Headers.Any("password", forKey: "xxx-api-key")
        }

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/javascript")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "localhost:8080")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password")
    }

    func testCollisionHeaders() async {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.ContentType(.webp)
            Headers.Accept(.jpeg)
            Headers.Any("password", forKey: "xxx-api-key")
            Headers.Any("password123", forKey: "xxx-api-key")
        }

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/webp")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/jpeg")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password123")
    }

    func testCollisionHeadersWithGroup() async {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.Accept(.jpeg)
            Headers.Any("password", forKey: "xxx-api-key")

            HeaderGroup {
                Headers.ContentType(.webp)
                Headers.Any("password123", forKey: "xxx-api-key")
            }
        }

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/webp")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/jpeg")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password123")
    }

    func testCombinedHeadersWithGroup() async {
        let property = TestProperty {
            Headers.Host("localhost", port: "8080")

            HeaderGroup {
                Headers.ContentType(.webp)
                Headers.Any("password", forKey: "xxx-api-key")
            }

            Headers.Accept(.jpeg)
            Headers.Origin("google.com")
        }

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Host"), "localhost:8080")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/webp")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/jpeg")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "google.com")
    }
}
