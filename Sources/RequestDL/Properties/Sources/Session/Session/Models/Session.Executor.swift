//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

extension Session {

    /// The transport a session ultimately executes its requests through.
    public enum Executor: Sendable, Hashable {
        /// Apple's `URLSession`.
        case urlSession
        /// SwiftNIO's Network.framework transport (`NIOTransportServices`).
        case nioTransportServices
        /// Plain SwiftNIO -- the universal fallback available on every supported platform.
        case nio

        // MARK: - Inits

        init(_ executor: Internals.Executor) {
            switch executor {
            case .urlSession:
                self = .urlSession
            case .nioTransportServices:
                self = .nioTransportServices
            case .nio:
                self = .nio
            }
        }

        // MARK: - Internal methods

        func build() -> Internals.Executor {
            switch self {
            case .urlSession:
                return .urlSession
            case .nioTransportServices:
                return .nioTransportServices
            case .nio:
                return .nio
            }
        }
    }
}
