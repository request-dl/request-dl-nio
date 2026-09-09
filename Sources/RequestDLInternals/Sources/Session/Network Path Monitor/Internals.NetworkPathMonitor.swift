//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import Network
import SwiftAsyncStream

extension Internals {

    /// A shared, process-lifetime wrapper around a single `NWPathMonitor`, fanning its updates
    /// out to any number of concurrent ``updates()`` subscribers.
    ///
    /// One `NWPathMonitor` for the whole process, not one per request/gate call -- starting a
    /// fresh monitor has real overhead. Lazily created via `.shared`'s own thread-safe lazy
    /// static initialization, so a process that never sets `allowsCellularAccess`/
    /// `allowsExpensiveNetworkAccess`/`allowsConstrainedNetworkAccess`/`waitsForConnectivity`
    /// never starts an `NWPathMonitor` at all -- `Internals.NetworkPathGate.wait(for:)` is only
    /// ever called when at least one of those four is set, and `.shared` is only referenced from
    /// inside that call's default `observer` argument.
    package final class NetworkPathMonitor: NetworkPathObserving, @unchecked Sendable {

        package static let shared = NetworkPathMonitor()

        private let monitor = NWPathMonitor()
        private let queue = DispatchQueue(label: "RequestDL.NetworkPathMonitor")
        private let lock = Lock()

        /// Guarded by `lock`.
        private var _currentPath: NetworkPath

        /// Guarded by `lock`. Keyed by subscription identity so each `updates()` call can
        /// deregister only its own continuation on termination.
        private var _subscribers: [ObjectIdentifier: _Concurrency.AsyncStream<NetworkPath>.Continuation] = [:]

        package var currentPath: NetworkPath {
            lock.withLock { _currentPath }
        }

        // MARK: - Inits

        private init() {
            _currentPath = monitor.currentPath.toNetworkPath
            monitor.pathUpdateHandler = { [weak self] path in
                self?.updatePath(path.toNetworkPath)
            }
            monitor.start(queue: queue)
        }

        // MARK: - Internal methods

        package func updates() -> _Concurrency.AsyncStream<NetworkPath> {
            let token = SubscriberToken()
            let id = ObjectIdentifier(token)

            return _Concurrency.AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                let initialPath = lock.withLock { () -> NetworkPath in
                    _subscribers[id] = continuation
                    return _currentPath
                }

                // A path that already satisfies by the time a caller subscribes must not wait
                // for the *next* change to be observed.
                continuation.yield(initialPath)

                // Fires when this stream's consuming task is cancelled. This is the
                // cancellation-safety hook `Internals.NetworkPathGate.wait(for:)` relies on: it
                // removes the dead subscriber so `updatePath` stops retaining/yielding to it,
                // with no separate cancellation plumbing needed in the gate itself.
                continuation.onTermination = { [weak self, token] _ in
                    _ = token
                    self?.lock.withLock { self?._subscribers[id] = nil }
                }
            }
        }

        // MARK: - Private methods

        private func updatePath(_ path: NetworkPath) {
            let subscribers = lock.withLock { () -> [_Concurrency.AsyncStream<NetworkPath>.Continuation] in
                _currentPath = path
                return Array(_subscribers.values)
            }

            for continuation in subscribers {
                continuation.yield(path)
            }
        }

        /// Identity anchor for a single `updates()` subscription -- kept alive by its own
        /// `onTermination` closure until termination fires, then released.
        private final class SubscriberToken: Sendable {}
    }
}

extension NWPath {

    fileprivate var toNetworkPath: Internals.NetworkPath {
        .init(
            isSatisfied: status == .satisfied,
            usesCellular: usesInterfaceType(.cellular),
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }
}
#endif
