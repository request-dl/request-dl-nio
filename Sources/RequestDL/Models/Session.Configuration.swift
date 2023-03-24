/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

extension Session {

    public enum Configuration {

        case `default`

        case identifier(String, numberOfThreads: Int = ProcessInfo.processInfo.activeProcessorCount)

        case custom(EventLoopGroup)
    }
}

extension Session.Configuration {

    func build() -> RequestDLInternals.Session.Provider {
        switch self {
        case .default:
            return .shared
        case .identifier(let string, let numberOfThreads):
            return .identifier(string, numberOfThreads: numberOfThreads)
        case .custom(let eventLoopGroup):
            return .custom(eventLoopGroup)
        }
    }
}
