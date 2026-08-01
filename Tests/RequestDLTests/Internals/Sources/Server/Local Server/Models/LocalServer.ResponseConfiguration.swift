//
// See LICENSE for this package's licensing information.
//

import NIO
import NIOHTTP1
import NIOSSL

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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
