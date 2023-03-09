/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class DelegateProxyTests: XCTestCase {

    func testHelloWorld() async throws {
        XCTAssertEqual("Hello World!", "Hello World!")
    }
}
