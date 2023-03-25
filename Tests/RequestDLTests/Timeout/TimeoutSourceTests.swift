/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class TimeoutSourceTests: XCTestCase {

    func testRequestTimeout() async throws {
        let requestTimeout = Timeout.Source.request
        XCTAssertEqual(requestTimeout.rawValue, 1 << 0)
    }

    func testResourceTimeout() async throws {
        let resourceTimeout = Timeout.Source.resource
        XCTAssertEqual(resourceTimeout.rawValue, 1 << 1)
    }

    func testAllTimeout() async throws {
        let allTimeout = Timeout.Source.all
        XCTAssertEqual(allTimeout, [.request, .resource])
    }
}
