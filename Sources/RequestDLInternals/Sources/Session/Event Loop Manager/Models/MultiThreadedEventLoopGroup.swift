//
// See LICENSE for this package's licensing information.
//

import NIOPosix

extension MultiThreadedEventLoopGroup {

    package static let shared = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}
