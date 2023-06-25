/*
 See LICENSE for this package's licensing information.
*/

import Foundation
#if canImport(Network)
import NIOTransportServices

extension NIOTSEventLoopGroup {

    static let shared = NIOTSEventLoopGroup()
}
#endif
