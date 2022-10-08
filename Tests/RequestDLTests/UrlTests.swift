//
//  UrlTests.swift
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

final class UrlTests: XCTestCase {

    var delegate: DelegateProxy!

    override func setUp() async throws {
        delegate = .init()
    }

    override func tearDown() async throws {
        delegate = nil
    }

    func testValidURL() async {
        let sut1 = Url("https://google.com")
        let sut2 = Url("https://www.apple.com/iphone")
        let sut3 = Url("http://account.microsoft.com/account/account?q=teste")

        let (_, request1) = await Resolver(sut1).make(delegate)
        let (_, request2) = await Resolver(sut2).make(delegate)
        let (_, request3) = await Resolver(sut3).make(delegate)

        XCTAssertEqual(request1.url?.absoluteString, "https://google.com")
        XCTAssertEqual(request2.url?.absoluteString, "https://www.apple.com/iphone")
        XCTAssertEqual(request3.url?.absoluteString, "http://account.microsoft.com/account/account?q=teste")
    }

    func testValidURLProtocol() async {
        let sut1 = Url(.https, path: "google.com")
        let sut2 = Url(.https, path: "www.apple.com/iphone")
        let sut3 = Url(.http, path: "account.microsoft.com/account/account?q=teste")

        let (_, request1) = await Resolver(sut1).make(delegate)
        let (_, request2) = await Resolver(sut2).make(delegate)
        let (_, request3) = await Resolver(sut3).make(delegate)

        XCTAssertEqual(request1.url?.absoluteString, "https://google.com")
        XCTAssertEqual(request2.url?.absoluteString, "https://www.apple.com/iphone")
        XCTAssertEqual(request3.url?.absoluteString, "http://account.microsoft.com/account/account?q=teste")
    }

    func testNever() {
        XCTAssertTrue(Url.Body.self == Never.self)
    }

    func testCombineURLPlusUrl() async {
        let lhs = Url("https://google.com")
        let rhs = Url("/?q=apple")

        let sut = lhs + rhs

        let (_, request) = await Resolver(sut).make(delegate)

        XCTAssertEqual(request.url?.absoluteString, "https://google.com/?q=apple")
    }

    func testCombineProtocolUrlPlusString() async {
        let lhs = Url(.http, path: "account.microsoft.com/account")
        let rhs = "/user/10/profile.html"

        let sut = lhs + rhs

        let (_, request) = await Resolver(sut).make(delegate)

        XCTAssertEqual(request.url?.absoluteString, "http://account.microsoft.com/account\(rhs)")
    }

    func testCombineUrlPlusString() async {
        let lhs = Url("https://apple.com")
        let rhs = "/iphone"

        let sut = lhs + rhs

        let (_, request) = await Resolver(sut).make(delegate)

        XCTAssertEqual(request.url?.absoluteString, "https://apple.com/iphone")
    }

    func testEquatable() async {
        XCTAssertEqual(Url("https://google.com"), Url("https://google.com"))
        XCTAssertEqual(Url(.http, path: "google.com"), Url(.http, path: "google.com"))

        XCTAssertNotEqual(Url("apple.com"), Url("google.com"))
        XCTAssertNotEqual(Url(.https, path: "microsoft.com"), Url("apple.com"))
    }
}
