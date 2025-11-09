/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct TimeoutSourceTests {

    @Test
    func requestTimeout() async throws {
        let requestTimeout = Timeout.Source.connect
        #expect(requestTimeout.rawValue == 1 << 0)
    }

    @Test
    func resourceTimeout() async throws {
        let resourceTimeout = Timeout.Source.read
        #expect(resourceTimeout.rawValue == 1 << 1)
    }

    @Test
    func allTimeout() async throws {
        let allTimeout = Timeout.Source.all
        #expect(allTimeout == [.connect, .read])
    }
}
