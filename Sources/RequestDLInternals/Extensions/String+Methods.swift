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
}

extension Array where Element == String {

    /// Joins path components with single separators, dropping empties.
    ///
    /// Each component is trimmed of anything a path may not contain, and of its own slashes, so
    /// `["a/", "/b/", "", "c"]` comes out as `"a/b/c"`. A trailing slash on the last component
    /// survives, because that is the difference between a directory and a file.
    package func joinedAsPath() -> String {
        var cleanedComponents = Array(
            lazy
                .map { component in
                    component.trimming { !$0.isURLPathAllowed || $0 == "/" }
                }
                .filter { !$0.isEmpty }
        )

        if let lastOriginal = last, lastOriginal.hasSuffix("/"), !cleanedComponents.isEmpty {
            cleanedComponents[cleanedComponents.count - 1] += "/"
        }

        return cleanedComponents.joined(separator: "/")
    }
}
