//
// See LICENSE for this package's licensing information.
//

import NIOPosix

extension MultiThreadedEventLoopGroup {

    static let shared = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}
