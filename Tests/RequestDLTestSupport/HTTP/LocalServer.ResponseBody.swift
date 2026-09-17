//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder
#endif

extension LocalServer {

    /// Synthesizes the JSON envelope every ``LocalServer`` backend (NIO or the Network.framework
    /// ``PortableServer``) sends back for a request, from the same inputs either one collects:
    /// how many body bytes it actually read off the wire, the configured response (if any) at
    /// the requested path, and whatever `Cookie`/`User-Agent` the client sent. One implementation
    /// so both backends answer identically.
    static func makeResponseBody(
        configuration: ResponseConfiguration?,
        receivedBytes: Int,
        incomeHeaders: Internals.HTTPHeaders?
    ) -> Data? {
        // `JSONValue` stands in for `JSONSerialization`'s `Any`, which is not part of
        // `FoundationEssentials`.
        let response = configuration.flatMap {
            try? JSONDecoder().decode(Internals.JSONValue.self, from: $0.data)
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
        if let cookie = incomeHeaders?.first(name: "Cookie") {
            jsonObject["receivedCookieHeader"] = .string(cookie)
        }

        if let userAgent = incomeHeaders?.first(name: "User-Agent") {
            jsonObject["receivedUserAgentHeader"] = .string(userAgent)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(jsonObject)
    }

    /// `headers` with any existing `Content-Length` dropped and `length` appended instead.
    /// `Internals.HTTPHeaders` has no `replaceOrAdd`, unlike `NIOHTTP1.HTTPHeaders`: this is the
    /// one call site that needs it, so it's local instead of added to that general-purpose type.
    static func headers(_ headers: Internals.HTTPHeaders, replacingContentLengthWith length: Int) -> Internals.HTTPHeaders {
        var result = Internals.HTTPHeaders(
            headers
                .filter { $0.name.lowercased() != "content-length" }
                .map { ($0.name, $0.value) }
        )
        result.add(name: "Content-Length", value: String(length))
        return result
    }
}
