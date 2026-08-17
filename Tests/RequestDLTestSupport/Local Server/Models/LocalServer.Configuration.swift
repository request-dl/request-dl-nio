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

        // Dedicated port for LocalServerConcurrencyTests, paired with `ServerManager.stress`
        // (see LocalServer.swift) so its 200-connection burst binds its own server/event loop
        // group instead of competing with every other LocalServer-backed suite for `.standard`.
        static var stress: Configuration {
            .init(
                host: "localhost",
                port: 8889,
                option: .none
            )
        }

        let host: String
        let port: UInt
        let option: TLSOption
    }
}
