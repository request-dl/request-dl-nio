//
// See LICENSE for this package's licensing information.
//

import Logging
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct TaskMethodsTests {

    @Test
    func pinging() async throws {
        // Given
        let data = Data()

        // When
        try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .ping(10)
    }

    @Test
    func pinging_whenTimesIsZero_returnsImmediately() async throws {
        // Given
        let data = Data()

        // When
        try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .ping(0)
    }

    @Test
    func pinging_whenLoggerIsProvided_usesLoggerModifier() async throws {
        // Given
        let data = Data()

        // `Logger.debug(_:)`'s message is `@autoclosure`, only evaluated once the logger's own
        // level admits `.debug` — the default level is `.info`, which would silently skip the
        // "Pinging N started/succeeded" interpolations without exercising them.
        var logger = Logger(label: "RequestDLTests.TaskMethodsTests")
        logger.logLevel = .trace

        // When
        try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .ping(1, logger: logger)
    }
}
