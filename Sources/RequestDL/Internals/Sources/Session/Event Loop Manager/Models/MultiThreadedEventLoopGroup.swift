/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOPosix

extension MultiThreadedEventLoopGroup {

    static let shared = MultiThreadedEventLoopGroup(
        numberOfThreads: ProcessInfo.processInfo.activeProcessorCount
    )
}
