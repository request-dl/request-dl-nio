//
//  RequestMethodTests.swift
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

final class RequestMethodTests: XCTestCase {

    /**
     Reference test case:

         let property = TestProperty(RequestMethod(.get))
         let (_, request) = await resolve(property)
         XCTAssertEqual(request.httpMethod, "GET")

     Other ways to initialize:

         RequestMethod(.head) :: expects "HEAD"
         RequestMethod(.post) :: expects "POST"
         RequestMethod(.put) :: expects "PUT"
         RequestMethod(.delete) :: expects "DELETE"
         RequestMethod(.connect) :: expects "CONNECT"
         RequestMethod(.options) :: expects "OPTIONS"
         RequestMethod(.trace) :: expects "TRACE"
         RequestMethod(.patch) :: expects "PATCH"
     */

    func testGetHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.get))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testHeadHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.head))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.httpMethod, "HEAD")
    }

    func testPostHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.post))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testPutHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.put))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.httpMethod, "PUT")
    }

    func testDeleteHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.delete))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.httpMethod, "DELETE")
    }

    func testConnectHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.connect))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.httpMethod, "CONNECT")
    }

    func testOptionsHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.options))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.httpMethod, "OPTIONS")
    }

    func testTraceHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.trace))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.httpMethod, "TRACE")
    }

    func testPatchHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.patch))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.httpMethod, "PATCH")
    }
}
