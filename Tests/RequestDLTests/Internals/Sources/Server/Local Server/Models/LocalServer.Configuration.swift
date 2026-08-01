//
// See LICENSE for this package's licensing information.
//

import NIO
import NIOHTTP1
import NIOSSL

@testable import RequestDL

extension LocalServer {

    struct Configuration: Sendable, Hashable {

        static var standard: Configuration {
            .init(
                host: "localhost",
                port: 8888,
                option: .none
            )
        }

        let host: String
        let port: UInt
        let option: TLSOption
    }
}
