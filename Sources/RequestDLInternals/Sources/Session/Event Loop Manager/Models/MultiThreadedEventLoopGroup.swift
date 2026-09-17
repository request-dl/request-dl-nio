//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import NIOPosix

extension MultiThreadedEventLoopGroup {

    package static let shared = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}

#endif
