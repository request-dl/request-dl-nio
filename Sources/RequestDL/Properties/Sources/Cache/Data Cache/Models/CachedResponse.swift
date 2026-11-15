//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#endif

struct CachedResponse: Sendable, Codable, Hashable {

    // MARK: - Internal properties

    let response: Internals.ResponseHead

    let policy: DataCache.Policy.Set

    let date: Date

    /// What the request that produced `response` sent for each header the response says it
    /// varies on (`Vary`), by lowercased name, `""` for a header it did not send.
    ///
    /// The cache is keyed by URL alone, so this is what tells a later request whether the stored
    /// response is one it may be given (RFC 9111 §4.1). `nil` for an entry stored without it,
    /// which therefore matches no request when the response varies.
    let varyRequestHeaders: [String: String]?

    // MARK: - Inits

    init(
        response: Internals.ResponseHead,
        policy: DataCache.Policy.Set,
        varyRequestHeaders: [String: String]? = nil,
        date: Date = Date()
    ) {
        self.response = response
        self.policy = policy
        self.date = date
        self.varyRequestHeaders = varyRequestHeaders
    }

    // MARK: - Internal methods

    /// Whether `self` is `other` as a revalidation leaves an entry: the same response, with a
    /// fresh date and the freshness headers (`Cache-Control`, `Expires`, `Age`) the server sent
    /// along with its 304.
    ///
    /// What identifies an entry is everything else: the status, the validators, the credential
    /// digests it was stored for. Revalidations that run side by side each stamp their own date
    /// on it, so the date cannot be part of that; a record written for another account, or a new
    /// response for the key, differs in what is compared here.
    func isSameEntry(as other: CachedResponse) -> Bool {
        policy == other.policy
            && varyRequestHeaders == other.varyRequestHeaders
            && response.url == other.response.url
            && response.status == other.response.status
            && response.version == other.response.version
            && response.isKeepAlive == other.response.isKeepAlive
            && Self.identifyingHeaders(of: response) == Self.identifyingHeaders(of: other.response)
    }

    // MARK: - Private static methods

    private static let revalidatedHeaders: Set<String> = ["cache-control", "expires", "age"]

    /// The headers a revalidation does not rewrite, without regard to their order, which
    /// rewriting the others changes.
    private static func identifyingHeaders(of response: Internals.ResponseHead) -> [String] {
        response.headers
            .filter { !revalidatedHeaders.contains($0.name.lowercased()) }
            .map { $0.name.lowercased() + "\u{0}" + $0.value }
            .sorted()
    }
}
