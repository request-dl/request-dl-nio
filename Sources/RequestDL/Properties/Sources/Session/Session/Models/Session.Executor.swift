//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

extension Session {

    /// The transport a session ultimately executes its requests through.
    ///
    /// `.nioTransportServices`/`.nio` only exist in a build with NIO available, see
    /// `Internals.Executor`'s own doc comment. In a build without it, `.urlSession` is the only
    /// case, so `preferredExecutor(_:)`/`requiredExecutor(_:)` simply can't be called with
    /// anything else: the restriction is enforced by the type itself, at compile time, rather
    /// than by a runtime error.
    public enum Executor: Sendable, Hashable {
        /// Apple's `URLSession`.
        case urlSession
        #if canImport(NIOCore)
        /// SwiftNIO's Network.framework transport (`NIOTransportServices`).
        case nioTransportServices
        /// Plain SwiftNIO, the universal fallback available on every supported platform.
        case nio
        #endif

        // MARK: - Inits

        init(_ executor: Internals.Executor) {
            switch executor {
            case .urlSession:
                self = .urlSession
            #if canImport(NIOCore)
            case .nioTransportServices:
                self = .nioTransportServices
            case .nio:
                self = .nio
            #endif
            }
        }

        // MARK: - Internal methods

        func build() -> Internals.Executor {
            switch self {
            case .urlSession:
                return .urlSession
            #if canImport(NIOCore)
            case .nioTransportServices:
                return .nioTransportServices
            case .nio:
                return .nio
            #endif
            }
        }
    }
}
