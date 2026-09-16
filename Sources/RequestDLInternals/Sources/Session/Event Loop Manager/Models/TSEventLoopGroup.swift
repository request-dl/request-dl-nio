//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOTransportServices

extension NIOTSEventLoopGroup {

    package static let shared = NIOTSEventLoopGroup()
}
#endif
