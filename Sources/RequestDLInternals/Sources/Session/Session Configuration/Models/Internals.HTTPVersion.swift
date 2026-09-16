//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

extension Internals {

    package enum HTTPVersion: Sendable, Hashable {

        case http1Only
        case automatic

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() -> HTTPClient.Configuration.HTTPVersion {
            switch self {
            case .http1Only:
                return .http1Only
            case .automatic:
                return .automatic
            }
        }
        #endif
    }
}
