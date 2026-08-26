//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Enforces ``Session``'s `allowsCellularAccess`/`allowsExpensiveNetworkAccess`/
    /// `allowsConstrainedNetworkAccess`/`waitsForConnectivity` constraints in front of a request,
    /// since AsyncHTTPClient has no hook to configure the equivalent `NWParameters` itself (see
    /// swift-server/async-http-client#915 and #918, both closed with no path forward).
    ///
    /// Pre-flight only, checked once before the request is dispatched -- never re-evaluated once
    /// a transfer is under way. This matches `URLSession` itself: `waitsForConnectivity`/
    /// `taskIsWaitingForConnectivity` only ever cover the initial connection phase, and a network
    /// change mid-transfer surfaces there as an ordinary task error, not a retry. So this is
    /// parity with `URLSession`'s actual behavior, not a weaker stand-in for it.
    package enum NetworkPathGate {

        /// The subset of `Internals.Session.Configuration` this gate acts on.
        package struct Constraints: Sendable, Equatable {

            package var allowsCellularAccess: Bool?
            package var allowsExpensiveNetworkAccess: Bool?
            package var allowsConstrainedNetworkAccess: Bool?
            package var waitsForConnectivity: Bool?

            package init(
                allowsCellularAccess: Bool?,
                allowsExpensiveNetworkAccess: Bool?,
                allowsConstrainedNetworkAccess: Bool?,
                waitsForConnectivity: Bool?
            ) {
                self.allowsCellularAccess = allowsCellularAccess
                self.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
                self.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess
                self.waitsForConnectivity = waitsForConnectivity
            }
        }

        // MARK: - Internal static methods

        /// Returns once `observer.currentPath` satisfies `constraints`, throwing instead when it
        /// doesn't and either `constraints.waitsForConnectivity` isn't `true`, or the wait is
        /// cancelled before a satisfying path arrives.
        ///
        /// - Parameter observer: Defaults to the real, Darwin-only `NWPathMonitor`-backed
        /// singleton; falls back to an always-satisfied observer everywhere else, making this
        /// call an immediate no-op off Darwin. Overridable for tests.
        package static func wait(
            for constraints: Constraints,
            observer: any NetworkPathObserving = defaultObserver
        ) async throws {
            try Task.checkCancellation()

            if reason(for: observer.currentPath, constraints) == nil {
                return
            }

            guard constraints.waitsForConnectivity == true else {
                throw NetworkPathUnsatisfiedError(
                    reason: reason(for: observer.currentPath, constraints) ?? .noConnection,
                    waitedForConnectivity: false
                )
            }

            for await path in observer.updates() {
                if reason(for: path, constraints) == nil {
                    return
                }
            }

            // `observer.updates()` only ends when its consuming task is cancelled (see
            // `Internals.NetworkPathMonitor.updates()`'s `onTermination`), so reaching this point
            // means the wait was cancelled rather than that no satisfying path ever existed.
            try Task.checkCancellation()

            throw NetworkPathUnsatisfiedError(
                reason: reason(for: observer.currentPath, constraints) ?? .noConnection,
                waitedForConnectivity: true
            )
        }

        // MARK: - Private static methods

        /// The single source of truth for whether `path` satisfies `constraints`: `nil` means it
        /// does, any other value names the first constraint it violates, checked in this order --
        /// connectivity, then cellular, then expensive, then constrained.
        private static func reason(
            for path: NetworkPath,
            _ constraints: Constraints
        ) -> NetworkPathUnsatisfiedError.Reason? {
            guard path.isSatisfied else {
                return .noConnection
            }
            if constraints.allowsCellularAccess == false, path.usesCellular {
                return .cellularNotAllowed
            }
            if constraints.allowsExpensiveNetworkAccess == false, path.isExpensive {
                return .expensiveNotAllowed
            }
            if constraints.allowsConstrainedNetworkAccess == false, path.isConstrained {
                return .constrainedNotAllowed
            }
            return nil
        }

        #if canImport(Darwin)
        private static var defaultObserver: any NetworkPathObserving {
            NetworkPathMonitor.shared
        }
        #else
        private static var defaultObserver: any NetworkPathObserving {
            AlwaysSatisfiedObserver()
        }

        private struct AlwaysSatisfiedObserver: NetworkPathObserving {
            var currentPath: NetworkPath {
                .init(isSatisfied: true, usesCellular: false, isExpensive: false, isConstrained: false)
            }

            func updates() -> Swift.AsyncStream<NetworkPath> {
                Swift.AsyncStream { $0.finish() }
            }
        }
        #endif
    }
}
