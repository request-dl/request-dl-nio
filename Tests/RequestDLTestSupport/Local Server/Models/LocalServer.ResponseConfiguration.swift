//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONEncoder
#endif

extension LocalServer {

    struct ResponseConfiguration: Sendable {

        let status: HTTPStatus
        let headers: Internals.HTTPHeaders
        let data: Data

        init(status: HTTPStatus = .ok, headers: Internals.HTTPHeaders = .init(), data: Data) {
            self.status = status
            self.headers = headers
            self.data = data
        }

        /// Every call site passes a plain `String`, and `JSONEncoder` handles a bare top-level
        /// value the same way `JSONSerialization`'s `.fragmentsAllowed` used to, without needing
        /// `Foundation`.
        init<Value: Encodable>(
            status: HTTPStatus = .ok,
            headers: Internals.HTTPHeaders = .init(),
            jsonObject: Value
        ) throws {
            self.status = status
            self.headers = headers

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            self.data = try encoder.encode(jsonObject)
        }
    }
}
