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

final class MethodTests: XCTestCase {

    func testMethods() async {
        for method in MethodType.allCases {
            let sut = Group {
                BaseURL("google.com")
                Method(method)
            }

            let (_, request) = await resolve(sut)

            XCTAssertEqual(request.httpMethod, method.rawValue)
        }
    }

    func testMethodType() async {
        XCTAssertEqual(MethodType.get.rawValue, "GET")
        XCTAssertEqual(MethodType.head.rawValue, "HEAD")
        XCTAssertEqual(MethodType.post.rawValue, "POST")
        XCTAssertEqual(MethodType.put.rawValue, "PUT")
        XCTAssertEqual(MethodType.delete.rawValue, "DELETE")
        XCTAssertEqual(MethodType.connect.rawValue, "CONNECT")
        XCTAssertEqual(MethodType.options.rawValue, "OPTIONS")
        XCTAssertEqual(MethodType.trace.rawValue, "TRACE")
        XCTAssertEqual(MethodType.patch.rawValue, "PATCH")
    }

    func testNever() {
        XCTAssertTrue(Method.Body.self == Never.self)
    }
}
