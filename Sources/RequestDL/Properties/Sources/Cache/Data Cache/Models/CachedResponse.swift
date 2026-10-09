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
        varyRequestHeaders: [String: String]? = nil
    ) {
        self.response = response
        self.policy = policy
        self.date = Date()
        self.varyRequestHeaders = varyRequestHeaders
    }
}
