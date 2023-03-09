/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class TimeoutSourceTests: XCTestCase {

    func testRequestTimeout() {
        let requestTimeout = Timeout.Source.request
        XCTAssertEqual(requestTimeout.rawValue, 1 << 0)
    }

    func testResourceTimeout() {
        let resourceTimeout = Timeout.Source.resource
        XCTAssertEqual(resourceTimeout.rawValue, 1 << 1)
    }

    func testAllTimeout() {
        let allTimeout = Timeout.Source.all
        XCTAssertEqual(allTimeout, [.request, .resource])
    }
}
