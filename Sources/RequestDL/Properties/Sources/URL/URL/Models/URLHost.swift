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

    /// Whether `host`, as `URLComponents.host` gives it back (the port is not in it), can be put
    /// after `"scheme://"`.
    ///
    /// `URLComponents.host` is percent-decoded: `"attacker.com%23.good.com"` is
    /// `"attacker.com#.good.com"` in it, a `#` that was not one in the string the caller wrote and
    /// validated. So, on top of ``isWellFormed(_:)``, it has no `@` (see ``hasUserInfo(decoded:)``),
    /// and:
    ///
    /// - no `:`, `[`, `]` or `%` unless it is an IPv6 literal between brackets. A `:` here was
    ///   `%3A` (or an IPv6 address), and `"127.0.0.1%3A6379"` would otherwise be a host with no
    ///   port to the caller and a port to the request. A `%` would be decoded a second time, when
    ///   the base URL is parsed again: `"%2523"` decoded once is `"%23"`.
    /// - in an IPv6 literal: hex digits, `:` and `.`, and optionally a zone (`%en0`) of
    ///   unreserved characters that does not start with something the second parse reads as an
    ///   escape.
    static func isWellFormed(decoded host: String) -> Bool {
        guard isWellFormed(host), !hasUserInfo(decoded: host) else {
            return false
        }

        guard host.hasPrefix("[") || host.hasSuffix("]") else {
            return !host.contains(where: { $0 == ":" || $0 == "[" || $0 == "]" || $0 == "%" })
        }

        guard host.hasPrefix("["), host.hasSuffix("]"), host.count > 2 else {
            return false
        }

        let literal = host.dropFirst().dropLast()
        let address = literal.prefix { $0 != "%" }

        guard !address.isEmpty, address.allSatisfy({ $0 == ":" || $0 == "." || $0.isHexDigit && $0.isASCII }) else {
            return false
        }

        guard address.count < literal.count else {
            return true
        }

        let zone = literal.dropFirst(address.count + 1)

        return !zone.isEmpty
            && zone.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" || $0 == "~")
            }
            && !zone.prefix(2).allSatisfy { $0.isHexDigit && $0.isASCII }
    }
}
