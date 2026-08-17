//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import NIOTransportServices

extension NIOTSEventLoopGroup {

    package static let shared = NIOTSEventLoopGroup()
}
#endif
