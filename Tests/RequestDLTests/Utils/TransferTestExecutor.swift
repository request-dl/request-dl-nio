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

    /// A session that can only run on this executor: a request that would fall back to another one
    /// fails instead of passing for the wrong reason.
    var session: Session {
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
