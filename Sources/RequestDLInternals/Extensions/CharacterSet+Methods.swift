//
// See LICENSE for this package's licensing information.
//

// Stands in for `Foundation.CharacterSet`, which is not part of `FoundationEssentials`. The sets
// are spelled out as ASCII ranges rather than looked up, which is also considerably faster than
// a `CharacterSet` membership test.
//
// - Note: Nothing in NIO covers this. Percent encoding exists inside `AsyncHTTPClient` but is
// internal to it, so there is no public API to defer to.

extension Character {

    /// Whether this character may appear unescaped in a URI query, per RFC 3986.
    ///
    /// - Important: Deliberately narrower than the grammar allows. RFC 3986 permits the
    /// sub-delims `!$&'()*+,;=` plus `:` and `@` in a query, and this rejects them. That is
    /// correct for encoding a single query *value*, where an unescaped `&` or `=` would be read
    /// as a separator, and wrong for encoding an assembled query string, which this must
    /// therefore never be handed.
    package var isRFC3986QueryAllowed: Bool {
        guard let ascii = asciiValue else {
            return false
        }

        switch ascii {
        case 48...57,  // 0-9
            65...90,  // A-Z
            97...122,  // a-z
            45,  // -
            46,  // .
            95,  // _
            126,  // ~
            47,  // /
            63:  // ?
            return true

        default:
            return false
        }
    }

    /// Whether this character may appear unescaped in a URI path, per RFC 3986.
    ///
    /// The full `pchar` production, plus `/`: unreserved, sub-delims, `:` and `@`.
    package var isURLPathAllowed: Bool {
        guard let ascii = asciiValue else {
            return false
        }

        switch ascii {
        case 48...57,  // 0-9
            65...90,  // A-Z
            97...122,  // a-z
            45,  // -
            46,  // .
            95,  // _
            126,  // ~
            33,  // !
            36,  // $
            38,  // &
            39,  // '
            40,  // (
            41,  // )
            42,  // *
            43,  // +
            44,  // ,
            59,  // ;
            61,  // =
            58,  // :
            64,  // @
            47:  // /
            return true

        default:
            return false
        }
    }

    /// Whether this character may appear in an HTTP `token`, per RFC 9110 §5.6.2.
    ///
    /// Used to keep the `User-Agent` header's `product` value well-formed: a `token` cannot be
    /// quoted or percent-encoded like the rest of a header value, so a disallowed character
    /// (a space in a process name, say) has to be substituted rather than escaped.
    package var isRFC9110TokenAllowed: Bool {
        guard let ascii = asciiValue else {
            return false
        }

        switch ascii {
        case 48...57,  // 0-9
            65...90,  // A-Z
            97...122,  // a-z
            33,  // !
            35,  // #
            36,  // $
            37,  // %
            38,  // &
            39,  // '
            42,  // *
            43,  // +
            45,  // -
            46,  // .
            94,  // ^
            95,  // _
            96,  // `
            124,  // |
            126:  // ~
            return true

        default:
            return false
        }
    }
}
