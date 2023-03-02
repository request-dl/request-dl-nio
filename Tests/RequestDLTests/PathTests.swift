//
//  File.swift
//
//
//  Created by Brenno on 02/03/23.
//

import XCTest
@testable import RequestDL

final class PathTests: XCTestCase {

    var delegate: DelegateProxy!

    override func setUp() async throws {
        delegate = .init()
    }

    override func tearDown() async throws {
        delegate = nil
    }

    func testValidPath() async {
        let sut1 = Test(Path("iphone"))
        let sut2 = Test(Path("mac"))
        let sut3 = Test(Path("music"))

        let (_, request1) = await resolve(sut1)
        let (_, request2) = await resolve(sut2)
        let (_, request3) = await resolve(sut3)

        XCTAssertEqual(request1.url?.absoluteString, "https://www.apple.com/iphone")
        XCTAssertEqual(request2.url?.absoluteString, "https://www.apple.com/mac")
        XCTAssertEqual(request3.url?.absoluteString, "https://www.apple.com/music")
    }

    func testMultiplePath() async {
        let sut1 = Test {
            Path("iphone")
            Path("overview")
            Path("spec-info")
        }

        let (_, request1) = await resolve(sut1)

        XCTAssertEqual(request1.url?.absoluteString, "https://www.apple.com/iphone/overview/spec-info")
    }
}
