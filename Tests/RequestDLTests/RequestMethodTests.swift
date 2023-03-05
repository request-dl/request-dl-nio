//
//  MethodTests.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
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

final class RequestMethodTests: XCTestCase {

    func testDescriptions() {
        XCTAssertEqual(HTTPMethod.get, "GET")
        XCTAssertEqual(HTTPMethod.head, "HEAD")
        XCTAssertEqual(HTTPMethod.post, "POST")
        XCTAssertEqual(HTTPMethod.put, "PUT")
        XCTAssertEqual(HTTPMethod.delete, "DELETE")
        XCTAssertEqual(HTTPMethod.connect, "CONNECT")
        XCTAssertEqual(HTTPMethod.options, "OPTIONS")
        XCTAssertEqual(HTTPMethod.trace, "TRACE")
        XCTAssertEqual(HTTPMethod.patch, "PATCH")
    }

    func testGetMethod() async {
        let property = Test(RequestMethod(.get))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testHeadMethod() async {
        let property = Test(RequestMethod(.head))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.httpMethod, "HEAD")
    }

    func testPostMethod() async {
        let property = Test(RequestMethod(.post))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testPutMethod() async {
        let property = Test(RequestMethod(.put))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.httpMethod, "PUT")
    }

    func testDeleteMethod() async {
        let property = Test(RequestMethod(.delete))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.httpMethod, "DELETE")
    }

    func testConnectMethod() async {
        let property = Test(RequestMethod(.connect))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.httpMethod, "CONNECT")
    }

    func testOptionsMethod() async {
        let property = Test(RequestMethod(.options))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.httpMethod, "OPTIONS")
    }

    func testTraceMethod() async {
        let property = Test(RequestMethod(.trace))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.httpMethod, "TRACE")
    }

    func testPatchMethod() async {
        let property = Test(RequestMethod(.patch))

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.httpMethod, "PATCH")
    }

    func testNever() {
        XCTAssertTrue(RequestMethod.Body.self == Never.self)
    }
}
