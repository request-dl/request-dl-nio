//
// See LICENSE for this package's licensing information.
//

// Replaces `Foundation.CharacterSet`, which is not part of `FoundationEssentials`. The sets are
// spelled out as ASCII ranges rather than looked up, which is also considerably faster than the
// `CharacterSet` membership test it replaced.
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
    var isRFC3986QueryAllowed: Bool {
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
    var isURLPathAllowed: Bool {
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
}
