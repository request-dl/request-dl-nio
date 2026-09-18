//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
#endif

extension LocalServer {

    /// Builds the JSON body every `LocalServer`-backed request gets back, shared by both the
    /// NIOHTTP1-pipeline `HTTPHandler` and the Network.framework `PortableServer`'s own
    /// hand-rolled HTTP/1.1 responder, so the two stay behaviorally identical regardless of which
    /// one a given build actually compiles.
    ///
    /// `JSONValue` stands in for `JSONSerialization`'s `Any`, which is not part of
    /// `FoundationEssentials`.
    static func makeResponseBody(
        configuredData: Data?,
        receivedBytes: Int,
        cookieHeader: String?,
        userAgentHeader: String?
    ) -> Data? {
        let response = configuredData.flatMap {
            try? JSONDecoder().decode(Internals.JSONValue.self, from: $0)
        }

        var jsonObject: [String: Internals.JSONValue] = [
            "receivedBytes": .integer(Int64(receivedBytes))
        ]

        if let response {
            jsonObject["response"] = response
        }

        // Lets a test prove what the client actually sent, not just what the server chose to
        // send back: e.g. confirming a cookie set by an earlier response was (or, under
        // `.urlSession`'s no-jar normalization, was *not*) resent automatically.
        if let cookieHeader {
            jsonObject["receivedCookieHeader"] = .string(cookieHeader)
        }

        if let userAgentHeader {
            jsonObject["receivedUserAgentHeader"] = .string(userAgentHeader)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(jsonObject)
    }
}
