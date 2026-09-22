//
// See LICENSE for this package's licensing information.
//

// This whole extension is the `.nio`/`.nioTransportServices` half of `Internals.ClientManager`
// (see its own doc comment below), so none of it exists at all without NIO.
#if canImport(NIOCore)

import NIOCore
import SwiftAsyncStream

/// The `.nio`/`.nioTransportServices` half of `Internals.ClientManager`, split out from the main
/// declaration (which stays in `Internals.ClientManager.swift`, alongside the shared table/lock
/// bookkeeping and the `.urlSession` half) because this half, and only this half, needs
/// `NIOCore.EventLoopGroup`/`Internals.Client`.
///
/// Reaches into the main declaration's `lock`/`tableLock`/`_table`/`_reusableItem(id:sessionConfiguration:)`,
/// none of which are `private` for exactly this reason: Swift has no "private to this type across
/// files" access level, so `internal` (the default) is as narrow as they can be while still being
/// reachable here.
extension Internals.ClientManager {

    package func client(
        provider: SessionProvider,
        sessionConfiguration: Internals.Session.Configuration
    ) async throws -> Internals.Client {
        try await _nioClient(
            provider: provider,
            sessionConfiguration: sessionConfiguration,
            isCompatibleWithNetworkFramework: sessionConfiguration.isCompatibleWithNetworkFramework
        )
    }

    /// Shared body for `client(provider:sessionConfiguration:)` and
    /// `resolvedClient(provider:sessionConfiguration:)`'s `.nio`/`.nioTransportServices` branch:
    /// the two differ only in *how* they decide `isCompatibleWithNetworkFramework` (the
    /// `enableNetworkFramework` flag directly, vs. `resolveExecutor()`'s own answer), never in
    /// what happens once that's decided.
    ///
    /// Not `fileprivate`: `resolvedClient(provider:sessionConfiguration:)`, in the main
    /// declaration's file, calls this too.
    func _nioClient(
        provider: SessionProvider,
        sessionConfiguration: Internals.Session.Configuration,
        isCompatibleWithNetworkFramework: Bool
    ) async throws -> Internals.Client {
        let options = SessionProviderOptions(
            isCompatibleWithNetworkFramework: isCompatibleWithNetworkFramework
        )

        let sessionProviderID = provider.uniqueIdentifier(with: options)

        return try await lock.withLock {
            // `AsyncLock` never aborts acquisition, so a task cancelled while queued behind
            // a cleanup sweep would otherwise still pay for (or trigger) client creation and
            // go on to fire a request nobody wants anymore. Checked first, before touching
            // the table, so a cancelled caller does no work at all here.
            try Task.checkCancellation()

            // `withLock` rather than a manual lock and unlock pair with a return in the
            // middle of it, which balances today and stops balancing on the next edit.
            //
            // Skipped outright for a configuration that can never match a pooled one: the scan
            // is linear, and for such a configuration it is guaranteed to walk the whole list and
            // find nothing, every single time.
            if sessionConfiguration.isPoolable,
                case .nio(let client) = tableLock.withLock({
                    _reusableItem(id: sessionProviderID, sessionConfiguration: sessionConfiguration)
                })
            {
                return client
            }

            let eventLoopGroup = await Internals.EventLoopGroupManager.shared.provider(
                provider,
                with: options
            )

            return try _createNewClient(
                id: sessionProviderID,
                eventLoopGroup: eventLoopGroup,
                sessionConfiguration: sessionConfiguration,
                isCompatibleWithNetworkFramework: isCompatibleWithNetworkFramework
            )
        }
    }

    /// - Warning: Lockless with respect to `tableLock`, which it takes itself.
    fileprivate func _createNewClient(
        id: String,
        eventLoopGroup: EventLoopGroup,
        sessionConfiguration: Internals.Session.Configuration,
        isCompatibleWithNetworkFramework: Bool
    ) throws -> Internals.Client {
        let output = try sessionConfiguration.build(
            isCompatibleWithNetworkFramework: isCompatibleWithNetworkFramework
        )
        #if canImport(Darwin)
        let client = Internals.Client(
            eventLoopGroupProvider: .shared(eventLoopGroup),
            configuration: output.httpClientConfiguration,
            localIdentityHandle: output.localIdentityHandle,
            maximumConcurrentConnections: sessionConfiguration.maximumConcurrentConnections
        )
        #else
        let client = Internals.Client(
            eventLoopGroupProvider: .shared(eventLoopGroup),
            configuration: output.httpClientConfiguration,
            maximumConcurrentConnections: sessionConfiguration.maximumConcurrentConnections
        )
        #endif

        // Tracked even when `isPoolable` is `false` and nothing will ever match this entry
        // again. The table is not only a reuse cache, it is also what owns a client for its
        // lifetime: `Internals.Client.deinit` shuts the underlying `HTTPClient` down, and the
        // caller's reference does not outlive the call that handed it out — it returns as soon
        // as the response head arrives, with the body still streaming. Dropping the entry here
        // therefore tore down the connection out from under the response that was using it.
        //
        // Skipping the *scan* is what removes this configuration's real cost (see
        // `client(provider:sessionConfiguration:)`); `maximumCount`'s eviction is what keeps the
        // entries it leaves behind from accumulating without bound.
        let evicted = tableLock.withLock {
            var items = _table[id] ?? []

            items.append(
                .createNew(
                    sessionConfiguration: sessionConfiguration,
                    client: .nio(client)
                )
            )

            _table[id] = items

            return _evictIfNeeded(protecting: .nio(client))
        }

        Internals.ClientManager.shutdownDetached(evicted)

        return client
    }
}

#endif
