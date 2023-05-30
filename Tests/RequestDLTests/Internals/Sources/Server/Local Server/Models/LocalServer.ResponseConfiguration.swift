/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif
import NIO
import NIOSSL
import NIOHTTP1
@testable import RequestDL

extension LocalServer {

    struct ResponseConfiguration: Sendable {

        let headers: NIOHTTP1.HTTPHeaders
        let data: Data

        init(headers: NIOHTTP1.HTTPHeaders = .init(), data: Data) {
            self.headers = headers
            self.data = data
        }

        init(headers: NIOHTTP1.HTTPHeaders = .init(), jsonObject: Any) throws {
            self.headers = headers
            self.data = try JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.sortedKeys, .fragmentsAllowed]
            )
        }
    }
}
