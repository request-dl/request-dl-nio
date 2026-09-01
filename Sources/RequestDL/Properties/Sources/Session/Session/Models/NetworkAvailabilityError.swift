//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// An error thrown when a request cannot proceed under the network-availability constraints
/// configured on ``Session`` — ``Session/allowsCellularAccess(_:)``,
/// ``Session/allowsExpensiveNetworkAccess(_:)``, ``Session/allowsConstrainedNetworkAccess(_:)``,
/// and ``Session/waitsForConnectivity(_:)``.
///
/// AsyncHTTPClient has no hook to configure these at the `NWParameters` level the way
/// `URLSessionConfiguration` does — see swift-server/async-http-client#915 and #918, both closed
/// without a path forward — so RequestDL enforces them itself with a pre-flight check against the
/// current network path, before the request is ever handed to AsyncHTTPClient.
///
/// That check runs exactly once, right before the request starts. It is not a mid-flight
/// watchdog: like `URLSession`, which only waits for connectivity during a task's initial
/// connection phase, RequestDL never re-evaluates the network path once a transfer is under way —
/// a network change part way through a request surfaces as an ordinary transport error instead of
/// this one.
///
/// Under normal use this is only ever thrown on Apple platforms, where `Network.framework` is
/// available to check the current path; the four modifiers above have no effect anywhere else.
public struct NetworkAvailabilityError: Error, Sendable {

    /// Why the current network path did not satisfy the session's configured constraints.
    public enum Reason: Sendable, Hashable {
        /// The device currently has no usable network path at all.
        case noConnection
        /// The current path is cellular, and ``Session/allowsCellularAccess(_:)`` is `false`.
        case cellularNotAllowed
        /// The current path is expensive (for example, a personal hotspot or metered
        /// connection), and ``Session/allowsExpensiveNetworkAccess(_:)`` is `false`.
        case expensiveNotAllowed
        /// The current path is constrained (for example, Low Data Mode), and
        /// ``Session/allowsConstrainedNetworkAccess(_:)`` is `false`.
        case constrainedNotAllowed

        init(_ reason: Internals.NetworkPathUnsatisfiedError.Reason) {
            switch reason {
            case .noConnection:
                self = .noConnection
            case .cellularNotAllowed:
                self = .cellularNotAllowed
            case .expensiveNotAllowed:
                self = .expensiveNotAllowed
            case .constrainedNotAllowed:
                self = .constrainedNotAllowed
            }
        }
    }

    // MARK: - Public properties

    /// The specific reason the request could not proceed. When more than one constraint is
    /// violated at once, this reports whichever is checked first, in this order:
    /// ``Reason/noConnection``, ``Reason/cellularNotAllowed``, ``Reason/expensiveNotAllowed``,
    /// ``Reason/constrainedNotAllowed``.
    public let reason: Reason

    /// Whether ``Session/waitsForConnectivity(_:)`` was set to `true`. When `true`, RequestDL
    /// waited for a satisfying network path and the request was cancelled before one arrived;
    /// when `false` (`URLSessionConfiguration`'s own default), RequestDL failed immediately,
    /// without waiting at all.
    public let waitedForConnectivity: Bool

    // MARK: - Inits

    init(_ error: Internals.NetworkPathUnsatisfiedError) {
        self.reason = Reason(error.reason)
        self.waitedForConnectivity = error.waitedForConnectivity
    }
}

// MARK: - CustomStringConvertible

extension NetworkAvailabilityError: CustomStringConvertible {

    public var description: String {
        let reasonDescription: String

        switch reason {
        case .noConnection:
            reasonDescription = "the device currently has no usable network path"
        case .cellularNotAllowed:
            reasonDescription = "the current network path is cellular, and allowsCellularAccess(false) was set"
        case .expensiveNotAllowed:
            reasonDescription = "the current network path is expensive, and allowsExpensiveNetworkAccess(false) was set"
        case .constrainedNotAllowed:
            reasonDescription =
                "the current network path is constrained, and allowsConstrainedNetworkAccess(false) was set"
        }

        let waitNote =
            waitedForConnectivity
            ? "RequestDL waited for a satisfying path, but the request was cancelled before one arrived."
            : "RequestDL did not wait for connectivity — pass waitsForConnectivity(true) to Session to wait instead of failing immediately."

        return "RequestDL could not send this request: \(reasonDescription). \(waitNote)"
    }
}
