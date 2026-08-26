//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// What ``Internals/NetworkPathGate`` needs from a network path source, independent of
    /// `Network.framework` -- implemented by `Internals.NetworkPathMonitor` on Darwin, and by
    /// fakes in tests, so the gate's wait/fail logic can be exercised without ever touching a
    /// real `NWPathMonitor`.
    package protocol NetworkPathObserving: Sendable {

        /// The most recently observed path.
        var currentPath: NetworkPath { get }

        /// A fresh, independent subscription per call, immediately replaying `currentPath` to
        /// the new subscriber and then yielding every subsequent change. Ends when the
        /// subscribing task is cancelled.
        ///
        /// - Note: `Swift.AsyncStream`, explicitly qualified -- an unqualified reference here
        /// would resolve to `Internals.AsyncStream` instead, a throwing, replay-everything type
        /// meant for one-shot response bodies, a poor fit for a long-lived, ever-changing path
        /// signal.
        func updates() -> Swift.AsyncStream<NetworkPath>
    }
}
