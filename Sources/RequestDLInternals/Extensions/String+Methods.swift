//
// See LICENSE for this package's licensing information.
//

extension String {

    /// Percent encodes this string for use in a URI.
    ///
    /// - Parameter allowedCharacters: Characters to leave alone *in addition to* the RFC 3986
    /// query set. The predicate widens the set and cannot narrow it, so passing one that
    /// returns `false` everywhere, the default, means the query set alone.
    ///
    /// - Note: Encodes UTF-8 byte by byte, which is what RFC 3986 asks for. A character outside
    /// ASCII has no `asciiValue`, so it always takes the escaping path and comes out as one
    /// `%XX` per byte.
    package func addingRFC3986PercentEncoding(
        withAllowedCharacters allowedCharacters: (Character) -> Bool = { _ in false }
    ) -> String {
        var result = ""
        result.reserveCapacity(count)

        for character in self {
            if character.isRFC3986QueryAllowed || allowedCharacters(character) {
                result.append(character)
                continue
            }

            for byte in character.utf8 {
                result.append("%")

                let hex = String(byte, radix: 16, uppercase: true)

                if hex.count == 1 {
                    result.append("0")
                }

                result.append(hex)
            }

        }

        return result
    }

    /// Splits on the boundary before each uppercase character.
    ///
    /// `"contentType"` becomes `["content", "Type"]`. Used to turn a property name into header
    /// or query words.
    package func splitByUppercasedCharacters() -> [String] {
        reduce([String]()) {
            guard let last = $0.last else {
                return ["\($1)"]
            }

            let reduced = $0.dropLast()

            if let lastReducedCharacter = last.last, !lastReducedCharacter.isUppercase, $1.isUppercase {
                return reduced + [last] + ["\($1)"]
            }

            return reduced + ["\(last)\($1)"]
        }
    }

}

// MARK: - Trimming

// On `StringProtocol`, not `String`, so these also apply to a `Substring`. Everything that
// splits a header value works in slices, and `Foundation.trimmingCharacters(in:)`, which these
// replace, was available there too.
extension StringProtocol {

    /// Drops matching characters from the front.
    ///
    /// - Note: Was branching on `#available` to reach the standard library's
    /// `trimmingPrefix(while:)` above macOS 13, falling back to `drop(while:)` below it. The two
    /// do the same thing, so the availability check and its second code path are gone.
    package func trimmingPrefix(where shouldBeTrimmed: (Character) -> Bool) -> String {
        String(drop(while: shouldBeTrimmed))
    }

    /// Drops matching characters from both ends.
    package func trimming(where shouldBeTrimmed: (Character) -> Bool) -> String {
        let trimmedPrefix = drop(while: shouldBeTrimmed)

        guard !trimmedPrefix.isEmpty else {
            return ""
        }

        let trimmedSuffix = trimmedPrefix.reversed().drop(while: shouldBeTrimmed)
        return String(trimmedSuffix.reversed())
    }

    /// Replaces every character outside the RFC 9110 `token` grammar with `-`, so the result is
    /// safe to use unquoted as a `product` token in headers like `User-Agent`.
    ///
    /// - Note: Falls back to `"-"` when nothing survives (an empty or fully non-ASCII input),
    /// since an empty token would leave a stray `/` in `product/version`.
    package var sanitizedAsRFC9110Token: String {
        let sanitized = String(map { $0.isRFC9110TokenAllowed ? $0 : "-" })
        return sanitized.isEmpty ? "-" : sanitized
    }
}

// MARK: - Path encoding

extension StringProtocol {

    /// This text as it goes on the wire in a URL path, the way a URL string is canonicalized.
    ///
    /// - A `%` followed by two hexadecimal digits is a percent-encoded byte already and stays
    ///   one, with the digits in upper case (`%2f` and `%2F` are the same byte). That is what
    ///   keeps `%2F` a segment's own slash and `%25` a literal percent sign.
    /// - Anything else a path may not contain is encoded, one `%XX` per UTF-8 byte: a space, a
    ///   non-ASCII character, a `%` that is not part of an escape, `#`, `?`, `\`.
    ///
    /// Text that already means something else by an escape, such as `100%AB` that is meant to be
    /// the literal `100%AB`, can't be told apart from an encoded byte and is taken as one.
    package func addingPercentEncodingForURLPath() -> String {
        let bytes = Array(utf8)
        var result = ""
        result.reserveCapacity(bytes.count)

        var index = 0

        while index < bytes.count {
            let byte = bytes[index]

            if byte == UInt8(ascii: "%"),
                index + 2 < bytes.count,
                Self.isHexDigit(bytes[index + 1]),
                Self.isHexDigit(bytes[index + 2])
            {
                result.append("%")
                result.append(Character(UnicodeScalar(bytes[index + 1])).uppercased())
                result.append(Character(UnicodeScalar(bytes[index + 2])).uppercased())
                index += 3
                continue
            }

            if byte < 0x80, Character(UnicodeScalar(byte)).isURLPathAllowed {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result.append("%")
                let hex = String(byte, radix: 16, uppercase: true)
                result.append(hex.count == 1 ? "0\(hex)" : hex)
            }

            index += 1
        }

        return result
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
            UInt8(ascii: "a")...UInt8(ascii: "f"),
            UInt8(ascii: "A")...UInt8(ascii: "F"):
            return true
        default:
            return false
        }
    }
}

extension Array where Element == String {

    /// Joins path components with single separators, dropping empties, in the form that goes on
    /// the wire (see ``addingPercentEncodingForURLPath()``).
    ///
    /// Each component is trimmed of whitespace and of its own slashes, so
    /// `["a/", "/b/", "", "c"]` comes out as `"a/b/c"`. A trailing slash on the last component
    /// survives, because that is the difference between a directory and a file.
    package func joinedAsPath() -> String {
        var cleanedComponents = Array(
            lazy
                .map { component in
                    component.trimming { $0.isWhitespace || $0 == "/" }
                }
                .filter { !$0.isEmpty }
                .map { $0.addingPercentEncodingForURLPath() }
        )

        if let lastOriginal = last, lastOriginal.hasSuffix("/"), !cleanedComponents.isEmpty {
            cleanedComponents[cleanedComponents.count - 1] += "/"
        }

        return cleanedComponents.joined(separator: "/")
    }
}
