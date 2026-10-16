//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

/// The executors a transfer test (suspending, reconnecting) runs against, every one available in
/// this build, so each guarantee is checked by the same test body on all of them.
///
/// `.nioTransportServices` only exists where SwiftNIO's Network.framework transport does.
enum TransferTestExecutor: Sendable, CaseIterable, CustomTestStringConvertible {
    #if canImport(NIOCore)
    case nio
    #endif

    #if canImport(NIOCore) && canImport(Darwin)
    case nioTransportServices
    #endif

    #if canImport(Darwin)
    case urlSession
    #endif

    var testDescription: String {
        switch self {
        #if canImport(NIOCore)
        case .nio:
            return "nio"
        #endif
        #if canImport(NIOCore) && canImport(Darwin)
        case .nioTransportServices:
            return "nioTransportServices"
        #endif
        #if canImport(Darwin)
        case .urlSession:
            return "urlSession"
        #endif
        }
    }

    /// Whether this is one of the SwiftNIO executors, as opposed to `URLSession`.
    var isNIO: Bool {
        switch self {
        #if canImport(NIOCore)
        case .nio:
            return true
        #endif
        #if canImport(NIOCore) && canImport(Darwin)
        case .nioTransportServices:
            return true
        #endif
        #if canImport(Darwin)
        case .urlSession:
            return false
        #endif
        }
    }

    /// The session a transfer test runs under: pinned to this executor, and with an idle timeout
    /// far longer than any of these tests lets a transfer stay silent.
    ///
    /// A suspension, or a reader that has not caught up, does not count towards it. What does is a
    /// server (or a runner) that stops answering, and on a CI runner starved of CPU a moment can
    /// last minutes: the timeout would then fire for a reason that has nothing to do with what the
    /// test is checking. `ReadTimeoutTests` is where the timeout itself is checked.
    @PropertyBuilder
    var session: some Property {
        pinnedSession

        Timeout(.seconds(900), for: .read)
    }

    /// A session that can only run on this executor: a request that would fall back to another one
    /// fails instead of passing for the wrong reason.
    var pinnedSession: Session {
        switch self {
        #if canImport(NIOCore)
        case .nio:
            return Session().requiredExecutor(.nio)
        #endif
        #if canImport(NIOCore) && canImport(Darwin)
        case .nioTransportServices:
            return Session().requiredExecutor(.nioTransportServices)
        #endif
        #if canImport(Darwin)
        case .urlSession:
            return Session().requiredExecutor(.urlSession)
        #endif
        }
    }
}
