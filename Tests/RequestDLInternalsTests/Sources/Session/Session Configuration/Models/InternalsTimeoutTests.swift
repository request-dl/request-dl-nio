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

    /// `Hashable`/`Equatable` deliberately exclude `resource` and `read`, since `build()` below
    /// never forwards them and this type's equality is `Internals.ClientManager`'s pooled client
    /// cache key. Including them would make two otherwise-identical sessions differing only in
    /// `.timeout(.resource(_:))` or `.timeout(.read(_:))` produce byte-identical
    /// `HTTPClient.Configuration`s that are still treated as unpoolable.
    @Test
    func timeout_whenOnlyResourceDiffers_stillEquals() {
        // Given
        let lhs = Internals.Timeout(resource: 1_000_000_000)
        let rhs = Internals.Timeout(resource: 2_000_000_000)

        // Then
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test
    func timeout_whenOnlyReadDiffers_stillEquals() {
        // Given
        let lhs = Internals.Timeout(read: 1_000_000_000)
        let rhs = Internals.Timeout(read: 2_000_000_000)

        // Then
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    // MARK: - Idle

    /// An unset `read` is not "never": it is what `URLSession`'s `timeoutIntervalForRequest` has
    /// always defaulted to, applied to every executor by `Internals.IdleDeadline`.
    @Test
    func timeout_whenIdleWithoutRead_isSixtySeconds() {
        // Given
        let timeout = Internals.Timeout()

        // Then
        #expect(Internals.Timeout.defaultRead == 60_000_000_000)
        #expect(timeout.idle == 60_000_000_000)
    }

    @Test
    func timeout_whenIdleWithRead_isRead() {
        // Given
        let timeout = Internals.Timeout(read: 5_000_000_000)

        // Then
        #expect(timeout.idle == 5_000_000_000)
    }

    /// `Int64.max` is how a caller says never (`UnitTime.infinity`): no deadline at all.
    @Test
    func timeout_whenReadIsNever_hasNoIdleDeadline() {
        // Given
        let timeout = Internals.Timeout(read: .max)

        // Then
        #expect(Internals.IdleDeadline.make(nanoseconds: timeout.idle) == nil)
        #expect(Internals.IdleDeadline.make(nanoseconds: Internals.Timeout().idle) != nil)
    }

    #if canImport(NIOCore)
    @Test
    func timeout_whenBuild_mapsConnectToNanoseconds() {
        // Given
        let connect: Int64 = 60_000_000_000
        let timeout = Internals.Timeout(connect: connect, read: 30_000_000_000)

        // When
        let sut = timeout.build()

        // Then
        #expect(sut.connect == .nanoseconds(connect))
    }

    @Test
    func timeout_whenBuildWithNilFields_hasNoTimeouts() {
        // Given
        let timeout = Internals.Timeout()

        // When
        let sut = timeout.build()

        // Then
        #expect(sut.connect == nil)
        #expect(sut.read == nil)
    }

    /// AsyncHTTPClient's own read timeout is off whatever `read` says: it counts something
    /// different from what `URLSession`'s does (a download only, and it goes on counting while the
    /// application has the transfer suspended), so `Internals.IdleDeadline` enforces `read` the
    /// same way on every executor instead.
    @Test(arguments: [nil, 5_000_000_000, Int64.max] as [Int64?])
    func timeout_whenBuild_neverTurnsOnTheClientsOwnReadTimeout(read: Int64?) {
        // Given
        let timeout = Internals.Timeout(read: read)

        // When
        let sut = timeout.build()

        // Then
        #expect(sut.read == nil)
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
        #expect(sut.read == nil)
    }
    #endif
}
