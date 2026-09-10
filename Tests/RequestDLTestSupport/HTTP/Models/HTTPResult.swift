//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder
#endif

struct HTTPResult<Response: Codable>: Codable, Equatable where Response: Equatable {

    let receivedBytes: Int
    let response: Response

    /// The `Cookie` header value `LocalServer` actually received on this request, if any;
    /// `nil` for every existing response shape (defaulted, so this stays additive: no other
    /// construction or decode call site needs to change).
    ///
    /// `var`, not `let`: a `let` with an inline default is never decoded by the synthesized
    /// `init(from:)` at all; it would stay `nil` even when the JSON has the key. See
    /// `LocalServer.HTTPHandler.responseData()`.
    var receivedCookieHeader: String? = nil

    /// The `User-Agent` header value `LocalServer` actually received on this request, if any;
    /// same additive shape as ``receivedCookieHeader`` above.
    ///
    /// Lets a test prove what actually reached the wire: RequestDL's own neutral default, a
    /// caller-supplied value untouched, or, once dropped under `.urlSession`, URLSession's own
    /// native `CFNetwork`/`Darwin` report.
    var receivedUserAgentHeader: String? = nil
}

extension HTTPResult {

    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    init(_ data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}
