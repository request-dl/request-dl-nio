/*
 See LICENSE for this package's licensing information.
*/

import Foundation
#if os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS)
import NIOTransportServices

extension NIOTSEventLoopGroup {

    static let shared = NIOTSEventLoopGroup()
}
#endif
