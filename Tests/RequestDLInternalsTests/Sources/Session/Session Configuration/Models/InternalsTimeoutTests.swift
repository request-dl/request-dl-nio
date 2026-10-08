//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

// Only the `.build()` tests below need AsyncHTTPClient; `Internals.Timeout.build()` only exists
// under `canImport(NIOCore)` (it returns `HTTPClient.Configuration.Timeout`).
#if canImport(NIOCore)
import AsyncHTTPClient
#endif

struct InternalsTimeoutTests {

    @Test
    func timeout_whenDefault_allFieldsAreNil() {
        // Given
        let timeout = Internals.Timeout()

        // Then
        #expect(timeout.connect == nil)
        #expect(timeout.read == nil)
        #expect(timeout.resource == nil)
    }

    @Test
    func timeout_whenConnectSet_holdsItsValue() {
        // Given
        var timeout = Internals.Timeout()

        // When
        timeout.connect = 60_000_000_000

        // Then
        #expect(timeout.connect == 60_000_000_000)
        #expect(timeout.read == nil)
    }

    @Test
    func timeout_whenReadSet_holdsItsValue() {
        // Given
        var timeout = Internals.Timeout()

        // When
        timeout.read = 30_000_000_000

        // Then
        #expect(timeout.read == 30_000_000_000)
        #expect(timeout.connect == nil)
    }

    @Test
    func timeout_whenResourceSet_holdsItsValue() {
        // Given
        var timeout = Internals.Timeout()

        // When
        timeout.resource = 120_000_000_000

        // Then
        #expect(timeout.resource == 120_000_000_000)
    }

    @Test
    func timeout_whenEquals() {
        // Given
        let lhs = Internals.Timeout(connect: 1_000_000_000, read: 2_000_000_000)
        let rhs = Internals.Timeout(connect: 1_000_000_000, read: 2_000_000_000)

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func timeout_whenNotEquals() {
        // Given
        let lhs = Internals.Timeout(connect: 1_000_000_000)
        let rhs = Internals.Timeout(connect: 2_000_000_000)

        // Then
        #expect(lhs != rhs)
    }

    /// `Hashable`/`Equatable` deliberately exclude `resource`, since `build()` below never
    /// forwards it and this type's equality is `Internals.ClientManager`'s pooled client cache
    /// key. Including it would make two otherwise-identical sessions differing only in
    /// `.timeout(.resource(_:))` produce byte-identical `HTTPClient.Configuration`s that are
    /// still treated as unpoolable.
    @Test
    func timeout_whenOnlyResourceDiffers_stillEquals() {
        // Given
        let lhs = Internals.Timeout(resource: 1_000_000_000)
        let rhs = Internals.Timeout(resource: 2_000_000_000)

        // Then
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    #if canImport(NIOCore)
    @Test
    func timeout_whenBuild_mapsConnectAndReadToNanoseconds() {
        // Given
        let connect: Int64 = 60_000_000_000
        let read: Int64 = 30_000_000_000
        let timeout = Internals.Timeout(connect: connect, read: read)

        // When
        let sut = timeout.build()

        // Then
        #expect(sut.connect == .nanoseconds(connect))
        #expect(sut.read == .nanoseconds(read))
    }

    @Test
    func timeout_whenBuildWithNilFields_connectIsNilAndReadIsDefault() {
        // Given
        let timeout = Internals.Timeout()

        // When
        let sut = timeout.build()

        // Then
        #expect(sut.connect == nil)
        #expect(sut.read == .nanoseconds(Internals.Timeout.defaultRead))
    }

    /// AsyncHTTPClient has no idle read timeout of its own, so an unset `read` would leave a
    /// `.nio` request to a server that stops sending hanging forever, while `.urlSession` fails
    /// the same request after its 60 s `timeoutIntervalForRequest`.
    @Test
    func timeout_whenBuildWithoutRead_matchesURLSessionDefaultOfSixtySeconds() {
        // Given
        let timeout = Internals.Timeout()

        // When
        let sut = timeout.build()

        // Then
        #expect(Internals.Timeout.defaultRead == 60_000_000_000)
        #expect(sut.read == .seconds(60))
    }

    @Test
    func timeout_whenBuildWithExplicitRead_overridesDefault() {
        // Given
        let timeout = Internals.Timeout(read: 5_000_000_000)

        // When
        let sut = timeout.build()

        // Then
        #expect(sut.read == .seconds(5))
    }

    /// `resource` has no `HTTPClient.Configuration.Timeout` counterpart (see `Internals.Timeout
    /// .resource`'s own doc comment: `RawTask` reads it directly to drive
    /// `Internals.ResourceDeadline` instead), so `build()` must never forward it regardless of
    /// what `connect`/`read` are set to.
    @Test
    func timeout_whenBuild_doesNotForwardResource() {
        // Given
        var timeout = Internals.Timeout()
        timeout.resource = 120_000_000_000

        // When
        let sut = timeout.build()

        // Then
        #expect(sut.connect == nil)
        #expect(sut.read == .nanoseconds(Internals.Timeout.defaultRead))
    }
    #endif
}
