//
// See LICENSE for this package's licensing information.
//

/// What a host must look like to be put after `"scheme://"` in a base URL.
///
/// `BaseURL`, `FlexibleURL` and `URLOverride` all end up writing `"\(scheme)://\(host)"` into
/// `RequestConfiguration.baseURL`, a string that is parsed once more when the request is built.
/// A host that carries a character a URL parser treats as a delimiter would move what follows it
/// (the rest of the host, the `Path`, the `Query`) into another component of the URL, and send
/// the request to a different host than the one that was written.
enum URLHost {

    /// Whether `host` (`host` or `host:port`, as `BaseURL` takes it) can be put after
    /// `"scheme://"` without a parser reading something else than a host in it.
    ///
    /// It is not empty and has none of the characters that end the authority part of a URL, or
    /// that a URL parser treats as one: `/`, `?` and `#`, a backslash (read as `/` by some
    /// parsers), whitespace and control characters.
    static func isWellFormed(_ host: String) -> Bool {
        !host.isEmpty
            && !host.contains(where: { $0 == "/" || $0 == "?" || $0 == "#" || $0 == "\\" })
            && !host.unicodeScalars.contains(where: {
                $0.properties.isWhitespace || $0.value < 0x20 || $0.value == 0x7F
            })
    }

    /// Whether `host` carries what would be userinfo (`user@host`) once it is read again.
    static func hasUserInfo(decoded host: String) -> Bool {
        host.contains("@")
    }

    /// Whether `host`, as `URLComponents.host` gives it back, can be put after `"scheme://"`.
    ///
    /// `URLComponents.host` is percent-decoded: `"attacker.com%23.good.com"` is
    /// `"attacker.com#.good.com"` in it, a `#` that was not one in the string the caller wrote and
    /// validated. So, on top of ``isWellFormed(_:)``, it has no `@` (see ``hasUserInfo(decoded:)``)
    /// and no `%`: the base URL is parsed again, and `"%2523"` decoded once would be a `"%23"`
    /// that the second parse decodes into a `#`.
    static func isWellFormed(decoded host: String) -> Bool {
        isWellFormed(host) && !hasUserInfo(decoded: host) && !host.contains("%")
    }
}
