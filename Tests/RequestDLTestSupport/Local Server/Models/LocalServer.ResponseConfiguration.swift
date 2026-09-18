//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOHTTP1
#else
import RequestDLInternals
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONEncoder
#endif

extension LocalServer {

    struct ResponseConfiguration: Sendable {

        // Only ever differ from `NIOHTTP1`'s own types under a build with no NIOCore at all
        // (`LocalServer.HTTPStatus`/`Internals.HTTPHeaders`, see their own files): every existing
        // `LocalServer`-backed test still just writes `status: .found`/
        // `headers: ["...": "..."]`, unaware which pair of types it resolved to.
        #if canImport(NIOCore)
        typealias Status = NIOHTTP1.HTTPResponseStatus
        typealias Headers = NIOHTTP1.HTTPHeaders
        #else
        typealias Status = LocalServer.HTTPStatus
        typealias Headers = Internals.HTTPHeaders
        #endif

        let status: Status
        let headers: Headers
        let data: Data

        init(status: Status = .ok, headers: Headers = .init(), data: Data) {
            self.status = status
            self.headers = headers
            self.data = data
        }

        /// - Note: `Value: Encodable`, not `Any` plus `JSONSerialization` — every call site
        /// passes a `String`, and `JSONEncoder` handles a bare top-level value the same way
        /// `JSONSerialization`'s `.fragmentsAllowed` used to, without needing `Foundation`.
        init<Value: Encodable>(
            status: Status = .ok,
            headers: Headers = .init(),
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
