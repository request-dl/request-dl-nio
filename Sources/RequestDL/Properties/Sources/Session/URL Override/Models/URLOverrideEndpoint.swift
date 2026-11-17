//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.URLComponents
#endif

/// The parsed `"scheme://host[:port][/path]"` shape shared by both sides of a `URLOverride` rule.
///
/// Lives in `RequestDLInternals`, next to the session configuration the executors read the rules
/// from when they follow a redirect, so the first request and every later hop are matched by the
/// very same code. Only parsing a user-supplied string, which reports through ``URLOverrideError``,
/// is here.
typealias URLOverrideEndpoint = Internals.URLOverrides.Endpoint

extension URLOverrideEndpoint {

    /// Parses a user-supplied origin/destination string.
    ///
    /// A bare host (no `"scheme://"`) is rejected rather than defaulted, unlike ``BaseURL`` or
    /// ``FlexibleURL``: with two strings per rule instead of one, an implicit scheme would make
    /// it ambiguous which side of the pair a validation failure came from.
    init(parsing url: String) throws {
        // `Character.isWhitespace` already covers newlines, so this is the whole of
        // `.whitespacesAndNewlines` without needing `Foundation.CharacterSet`.
        let normalized = url.trimming(where: \.isWhitespace)

        guard let parsedURL = URL(string: normalized),
            let components = URLComponents(url: parsedURL, resolvingAgainstBaseURL: false)
        else {
            throw URLOverrideError(context: .invalidURL, url: url)
        }

        guard let scheme = components.scheme, !scheme.isEmpty else {
            throw URLOverrideError(context: .missingScheme, url: url)
        }

        guard let host = components.host, !host.isEmpty else {
            throw URLOverrideError(context: .missingHost, url: url)
        }

        // `components.host` is percent-decoded: `"attacker.com%23.good.com"` is
        // `"attacker.com#.good.com"` in it, and `Resolve` writes it as is in the base URL of a
        // request it rewrites. Same check as `BaseURL`.
        guard URLHost.isWellFormed(decoded: host) else {
            throw URLOverrideError(context: .invalidURL, url: url)
        }

        // `percentEncodedPath`, in the canonical form `RequestConfiguration.url` gives the request's
        // own path, so a rule written with `%2F` or a space matches the request it was written for.
        self.init(
            scheme: scheme,
            host: host,
            port: components.port,
            pathComponents: Array(
                components.percentEncodedPath
                    .split(separator: "/")
                    .lazy
                    .filter { !$0.isEmpty }
                    .map { $0.addingPercentEncodingForURLPath() }
            )
        )
    }
}
