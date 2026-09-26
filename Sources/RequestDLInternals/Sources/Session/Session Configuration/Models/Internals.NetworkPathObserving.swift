//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// What ``Internals/NetworkPathGate`` needs from a network path source, independent of
    /// `Network.framework`, implemented by `Internals.NetworkPathMonitor` on Darwin, and by
    /// fakes in tests, so the gate's wait/fail logic can be exercised without ever touching a
    /// real `NWPathMonitor`.
    package protocol NetworkPathObserving: Sendable {

        /// The most recently observed path.
        var currentPath: NetworkPath { get }

        /// The current path, once one has actually been observed.
        ///
        /// Differs from ``currentPath`` only before the source's first real update: a freshly
        /// started `NWPathMonitor` reports an unsatisfied placeholder until then (for a few
        /// milliseconds, on a fully connected device), and judging a request against that
        /// placeholder fails it with `.noConnection` for no reason. Defaults to ``currentPath``
        /// for sources that have no such startup window.
        func resolvedCurrentPath() async -> NetworkPath

        /// A fresh, independent subscription per call, immediately replaying the current path to
        /// the new subscriber (once one has been observed) and then yielding every subsequent
        /// change. Ends when the subscribing task is cancelled.
        ///
        /// - Note: `_Concurrency.AsyncStream`, explicitly qualified: an unqualified reference here
        /// would resolve to `Internals.AsyncStream` instead, a throwing, replay-everything type
        /// meant for one-shot response bodies, a poor fit for a long-lived, ever-changing path
        /// signal.
        func updates() -> _Concurrency.AsyncStream<NetworkPath>
    }
}

extension Internals.NetworkPathObserving {

    package func resolvedCurrentPath() async -> Internals.NetworkPath {
        currentPath
    }
}
