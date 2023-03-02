//
//  File.swift
//  
//
//  Created by Brenno on 02/03/23.
//

import XCTest
@testable import RequestDL

final class BaseURLTests: XCTestCase {

    var delegate: DelegateProxy!

    override func setUp() async throws {
        delegate = .init()
    }

    override func tearDown() async throws {
        delegate = nil
    }

    func testValidURL() async {
        let sut1 = BaseURL("google.com")
        let sut2 = BaseURL("www.apple.com/iphone")
        let sut3 = BaseURL("account.microsoft.com/account/account/q=teste")

        let (_, request1) = await resolve(sut1)
        let (_, request2) = await resolve(sut2)
        let (_, request3) = await resolve(sut3)

        XCTAssertEqual(request1.url?.absoluteString, "https://google.com")
        XCTAssertEqual(request2.url?.absoluteString, "https://www.apple.com")
        XCTAssertEqual(request3.url?.absoluteString, "https://account.microsoft.com")
    }

    func testValidURLProtocol() async {
        let sut1 = BaseURL(.https, host: "google.com")
        let sut2 = BaseURL(.https, host: "www.apple.com")
        let sut3 = BaseURL(.http, host: "account.microsoft.com")

        let (_, request1) = await resolve(sut1)
        let (_, request2) = await resolve(sut2)
        let (_, request3) = await resolve(sut3)

        XCTAssertEqual(request1.url?.absoluteString, "https://google.com")
        XCTAssertEqual(request2.url?.absoluteString, "https://www.apple.com")
        XCTAssertEqual(request3.url?.absoluteString, "http://account.microsoft.com")
    }
}
