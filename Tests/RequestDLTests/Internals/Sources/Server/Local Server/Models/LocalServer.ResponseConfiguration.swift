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
import struct Foundation.Data
import class Foundation.JSONEncoder
#endif

extension LocalServer {

    struct ResponseConfiguration: Sendable {

        let headers: NIOHTTP1.HTTPHeaders
        let data: Data

        init(headers: NIOHTTP1.HTTPHeaders = .init(), data: Data) {
            self.headers = headers
            self.data = data
        }

        /// - Note: `Value: Encodable`, not `Any` plus `JSONSerialization` — every call site
        /// passes a `String`, and `JSONEncoder` handles a bare top-level value the same way
        /// `JSONSerialization`'s `.fragmentsAllowed` used to, without needing `Foundation`.
        init<Value: Encodable>(headers: NIOHTTP1.HTTPHeaders = .init(), jsonObject: Value) throws {
            self.headers = headers

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            self.data = try encoder.encode(jsonObject)
        }
    }
}
