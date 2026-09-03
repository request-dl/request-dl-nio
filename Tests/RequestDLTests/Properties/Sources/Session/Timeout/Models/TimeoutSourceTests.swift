//
// See LICENSE for this package's licensing information.
//

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
    func resourceSourceRawValue() async throws {
        #expect(Timeout.Source.resource.rawValue == 1 << 2)
    }

    @Test
    func allTimeout() async throws {
        let allTimeout = Timeout.Source.all
        #expect(allTimeout == [.connect, .read])
    }

    /// `.resource` means something different from `.connect`/`.read` -- a total end-to-end
    /// deadline, not a per-phase one -- so it must never be folded into `.all`, or every existing
    /// `.all` caller would silently start getting a resource-wide deadline they never asked for.
    @Test
    func allTimeout_neverIncludesResource() async throws {
        #expect(!Timeout.Source.all.contains(.resource))
    }
}
