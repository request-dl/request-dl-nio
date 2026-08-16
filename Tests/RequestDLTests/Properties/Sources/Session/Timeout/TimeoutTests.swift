//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
import RequestDLInternals
@testable import RequestDLTestSupport

struct TimeoutTests {

    @Test
    func requestTimeout() async throws {
        // Given
        let requestTimeout = Timeout.Source.connect
        let timeout = UnitTime.seconds(75)

        // When
        let resolved = try await resolve(
            TestProperty {
                Timeout(timeout, for: requestTimeout)
            }
        )

        // Then
        #expect(resolved.session.configuration.timeout.connect == timeout.nanoseconds)
    }

    @Test
    func resourceTimeout() async throws {
        // Given
        let resourceTimeout = Timeout.Source.connect
        let timeout = UnitTime.seconds(1_999)

        // When
        let resolved = try await resolve(TestProperty(Timeout(timeout, for: resourceTimeout)))

        // Then
        #expect(resolved.session.configuration.timeout.connect == timeout.nanoseconds)
    }

    @Test
    func allTimeout() async throws {
        // Given
        let requestTimeout = Timeout.Source.all
        let timeout = UnitTime.seconds(75)

        // When
        let resolved = try await resolve(TestProperty(Timeout(timeout, for: requestTimeout)))

        // Then
        #expect(resolved.session.configuration.timeout.read == timeout.nanoseconds)
        #expect(resolved.session.configuration.timeout.connect == timeout.nanoseconds)
    }

    @Test
    func defaultTimeout() async throws {
        let defaultConfiguration = Internals.Session.Configuration()

        // When
        let resolved = try await resolve(TestProperty {})

        // Then
        #expect(
            resolved.session.configuration.timeout.read == defaultConfiguration.timeout.read
        )

        #expect(
            resolved.session.configuration.timeout.connect == defaultConfiguration.timeout.connect
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = Timeout(.seconds(1))

        // Then
        try await assertNever(property.body)
    }
}
