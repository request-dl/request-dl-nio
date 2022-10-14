//
//  TimeoutTests.swift
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

final class TimeoutTests: XCTestCase {

    var delegate: DelegateProxy!

    override func setUp() async throws {
        delegate = .init()
    }

    override func tearDown() async throws {
        delegate = nil
    }

    func testTimeoutAll() async {
        let sut = Group {
            Url("https:///google.com")
            Timeout(4, for: .all)
        }

        let (session, _) = await Resolver(sut).make(delegate)

        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 4)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 4)
    }

    func testTimeoutAllSeparated() async {
        let sut = Group {
            Url("https:///google.com")
            Timeout(2, for: .request)
            Timeout(6, for: .resource)
        }

        let (session, _) = await Resolver(sut).make(delegate)

        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 2)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 6)
    }

    func testTimeoutForRequest() async {
        let sut = Group {
            Url("https:///google.com")
            Timeout(1, for: .request)
        }

        let (session, _) = await Resolver(sut).make(delegate)

        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 1)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 7 * 24 * 3600)
    }

    func testTimeoutForResource() async {
        let sut = Group {
            Url("https:///google.com")
            Timeout(50, for: .resource)
        }

        let (session, _) = await Resolver(sut).make(delegate)

        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 60)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 50)
    }

    func testEmpty() async {
        let sut = Group {
            Url("https:///google.com")
        }

        let (session, _) = await Resolver(sut).make(delegate)

        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 60)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 7 * 24 * 3600)
    }

    func testNever() {
        XCTAssertTrue(Timeout.Body.self == Never.self)
    }
}


