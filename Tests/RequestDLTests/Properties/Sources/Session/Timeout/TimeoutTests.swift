//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
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
    func timeout_whenResourceSourceConfigured_setsResourceField() async throws {
        // Given
        let timeout = UnitTime.seconds(120)

        // When
        let resolved = try await resolve(
            TestProperty {
                Timeout(timeout, for: .resource)
            }
        )

        // Then
        #expect(resolved.session.configuration.timeout.resource == timeout.nanoseconds)
        #expect(resolved.session.configuration.timeout.connect == nil)
        #expect(resolved.session.configuration.timeout.read == nil)
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

    /// `.infinity` for `.read` is the opt-out: no deadline is built for it (see
    /// `Internals.IdleDeadline.make`), while a session that says nothing keeps the 60 seconds.
    @Test
    func timeout_whenReadIsInfinity_isNever() async throws {
        // When
        let resolved = try await resolve(TestProperty(Timeout(.infinity, for: .read)))
        let unset = try await resolve(TestProperty {})

        // Then
        #expect(resolved.session.configuration.timeout.read == .max)
        #expect(Internals.IdleDeadline.make(nanoseconds: resolved.session.configuration.timeout.idle) == nil)
        #expect(Internals.IdleDeadline.make(nanoseconds: unset.session.configuration.timeout.idle) != nil)
    }

    @Test
    func readTimeoutError_describesItself() {
        #expect(String(describing: ReadTimeoutError()).contains("Timeout(_:for: .read)"))
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = Timeout(.seconds(1))

        // Then
        try await assertNever(property.body)
    }
}
