//
// See LICENSE for this package's licensing information.
//

// `Internals.EventLoopGroupManager` and `SessionProvider.group(with:)` only exist under
// `canImport(NIOCore)`.
#if canImport(NIOCore)

import Dispatch
import NIOCore
import NIOPosix
import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsEventLoopManagerTests {

    struct CustomProvider: SessionProvider {

        let id = "test"
        private let _group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        func uniqueIdentifier(with options: SessionProviderOptions) -> String {
            id
        }

        func group(with options: SessionProviderOptions) -> EventLoopGroup {
            _group
        }
    }

    var options: SessionProviderOptions {
        SessionProviderOptions(
            isCompatibleWithNetworkFramework: true
        )
    }

    @Test
    func manager_whenRegisterGroup_shouldBeResolved() async throws {
        // Given
        let manager = Internals.EventLoopGroupManager()
        let provider = CustomProvider()

        // When
        let sut1 = await manager.provider(provider, with: options).group

        // Then
        #expect(provider.group(with: options) === sut1)
    }

    @Test
    func manager_whenRegisterIdentifier_shouldBeResolvedOnlyOnce() async throws {
        // Given
        let provider = CustomProvider()
        let manager = Internals.EventLoopGroupManager()

        // When
        let sut1 = await manager.provider(provider, with: options).group
        let sut2 = await manager.provider(provider, with: options).group

        // Then
        #expect(provider.group(with: options) === sut1)
        #expect(provider.group(with: options) === sut2)
    }

    /// Forwards everything to a real group, and records whether `Internals.EventLoopGroupManager`
    /// asked it to shut down.
    ///
    /// The obvious alternative — submitting work and seeing whether it runs — deadlocks: NIO
    /// silently *drops* work handed to a closed `EventLoop`, so the future it hands back never
    /// completes, in either direction. Recording the call is both deterministic and the thing
    /// actually under test.
    final class RecordingEventLoopGroup: EventLoopGroup, @unchecked Sendable {

        var wasShutDown: Bool {
            lock.withLock { _wasShutDown }
        }

        private let wrapped = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        private let lock = Lock()
        private var _wasShutDown = false

        func next() -> EventLoop {
            wrapped.next()
        }

        func any() -> EventLoop {
            wrapped.any()
        }

        func makeIterator() -> EventLoopIterator {
            wrapped.makeIterator()
        }

        func shutdownGracefully(queue: DispatchQueue, _ callback: @escaping ((Error?) -> Void)) {
            lock.withLock { _wasShutDown = true }
            wrapped.shutdownGracefully(queue: queue, callback)
        }
    }

    /// Stands in for `Internals.IdentifiedSessionProvider` (`createsGroup == true`) or for
    /// `Internals.CustomSessionProvider`/`SharedSessionProvider` (`false`), depending on what the
    /// test needs.
    struct RecordingProvider: SessionProvider {

        let id: String
        let recorded: RecordingEventLoopGroup
        let createsGroup: Bool

        func uniqueIdentifier(with options: SessionProviderOptions) -> String {
            id
        }

        func group(with options: SessionProviderOptions) -> EventLoopGroup {
            recorded
        }
    }

    private var posixOptions: SessionProviderOptions {
        SessionProviderOptions(isCompatibleWithNetworkFramework: false)
    }

    /// Fills `manager` past its ceiling with groups nothing else holds on to.
    private func pushPastTheCeiling(_ manager: Internals.EventLoopGroupManager, count: Int) async {
        for index in 0..<count {
            _ = await manager.provider(
                RecordingProvider(
                    id: "filler-\(index)",
                    recorded: RecordingEventLoopGroup(),
                    createsGroup: true
                ),
                with: posixOptions
            )
        }
    }

    /// `_groups` had no ceiling and nothing ever shut a group down, so every distinct
    /// `Session(_:numberOfThreads:)` identifier a process ever used kept its
    /// `MultiThreadedEventLoopGroup` — OS threads included — alive until the process exited.
    @Test
    func manager_whenMoreDistinctIdentifiersThanTheCap_shutsDownTheGroupsItBuiltItself() async throws {
        // Given
        let maximumCount = 4
        let manager = Internals.EventLoopGroupManager(maximumCount: maximumCount)
        let oldest = RecordingEventLoopGroup()

        _ = await manager.provider(
            RecordingProvider(id: "oldest", recorded: oldest, createsGroup: true),
            with: posixOptions
        )

        #expect(!oldest.wasShutDown)

        // When: enough other identifiers come through to push it out of the table.
        await pushPastTheCeiling(manager, count: maximumCount * 2)

        // Then: the table is bounded, and the evicted group's threads were genuinely retired
        // rather than merely dropped from the table and left spinning. Joined through the
        // manager's own signal, so this observes a finished shutdown instead of racing one.
        await manager.waitUntilShutdownsComplete()

        #expect(await manager.count <= maximumCount)
        #expect(oldest.wasShutDown)
    }

    /// Evicting is un-caching, never shutting down.
    ///
    /// `Internals.Client` holds an `EventLoopGroupToken` for exactly this reason: its pooled
    /// lifetime is governed by `Internals.ClientManager`, which knows nothing about this table,
    /// so an entry here can be evicted while clients are mid-request on that group. Retiring it
    /// then pulls the event loops out from under live connections — and an `HTTPClient` whose
    /// loops are gone can never complete its own `shutdown()`, which NIO traps on as a leaked
    /// promise.
    @Test
    func manager_whenAnEvictedGroupIsStillHeld_leavesItRunningUntilTheHolderLetsGo() async throws {
        // Given: a group whose token someone else is still holding, exactly as a live client
        // would be.
        let maximumCount = 2
        let manager = Internals.EventLoopGroupManager(maximumCount: maximumCount)
        let inUse = RecordingEventLoopGroup()

        var heldToken: Internals.EventLoopGroupToken? = await manager.provider(
            RecordingProvider(id: "in-use", recorded: inUse, createsGroup: true),
            with: posixOptions
        )

        // When: it is pushed out of the table.
        await pushPastTheCeiling(manager, count: maximumCount * 3)
        await manager.waitUntilShutdownsComplete()

        // Then: dropped from the cache, still very much running.
        #expect(heldToken != nil)
        #expect(await manager.count <= maximumCount)
        #expect(!inUse.wasShutDown)

        // And: retired the moment the last holder lets go, not a moment before.
        heldToken = nil

        await manager.waitUntilShutdownsComplete()
        #expect(inUse.wasShutDown)
    }

    /// The other half of the same change: a group this manager only *borrows* must never be shut
    /// down when it is evicted. `createsGroup == false` here stands for
    /// `Internals.CustomSessionProvider` (a group handed in through `Session.init(_:)`) and for
    /// `Internals.SharedSessionProvider` (NIO's process-wide singletons) alike — shutting either
    /// down would take every unrelated user of it along.
    @Test
    func manager_whenEvictingAGroupItDidNotBuild_leavesItRunning() async throws {
        // Given
        let maximumCount = 2
        let manager = Internals.EventLoopGroupManager(maximumCount: maximumCount)
        let borrowed = RecordingEventLoopGroup()

        _ = await manager.provider(
            RecordingProvider(id: "borrowed", recorded: borrowed, createsGroup: false),
            with: posixOptions
        )

        // When
        await pushPastTheCeiling(manager, count: maximumCount * 3)

        // Then: dropped from the table, but left entirely alone — checked after every shutdown
        // the eviction did start has finished, so this cannot pass merely by being quicker.
        await manager.waitUntilShutdownsComplete()

        #expect(await manager.count <= maximumCount)
        #expect(!borrowed.wasShutDown)
    }

    @Test
    func manager_whenRunningInBackground() async throws {
        // Given
        let provider = CustomProvider()
        let manager = Internals.EventLoopGroupManager()

        // When
        let sut = await _Concurrency.Task.detached(priority: .background) { [manager, options] in
            await manager.provider(provider, with: options).group
        }.value

        // Then
        #expect(sut === provider.group(with: options))
    }
}

#endif
