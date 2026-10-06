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

    /// The session a transfer test runs under: pinned to this executor, and with a client idle
    /// timeout far longer than any of these tests holds a transfer still.
    ///
    /// The transports' own idle timeouts (60 s by default on `.urlSession`) keep counting while a
    /// transfer is suspended, which is by design. A test only holds one suspended for a moment, but
    /// on a CI runner starved of CPU a moment can last minutes, and the timeout fires for a reason
    /// that has nothing to do with what the test is checking.
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
