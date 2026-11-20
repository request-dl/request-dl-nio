//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Splits a `Set-Cookie` value that a transport folded several headers into.
    ///
    /// `HTTPURLResponse.allHeaderFields` joins repeated headers with `", "`, and the `Expires`
    /// attribute has a comma of its own (`Wed, 01 Jan 2031`), so a plain split on commas cuts
    /// cookies in the middle of their date. A comma starts a new cookie here only when what follows
    /// it looks like `name=`: a token with no space, `;` or `,` before the first `=`.
    package enum SetCookieSplitter {

        package static func split(_ value: String) -> [String] {
            var cookies: [String] = []
            var current = ""
            var index = value.startIndex

            while index < value.endIndex {
                let character = value[index]

                if character == ",", startsCookie(after: value.index(after: index), in: value) {
                    cookies.append(current)
                    current = ""
                } else {
                    current.append(character)
                }

                index = value.index(after: index)
            }

            cookies.append(current)
            return cookies.map { $0.trimmingWhitespace() }.filter { !$0.isEmpty }
        }

        // MARK: - Private static methods

        private static func startsCookie(after index: String.Index, in value: String) -> Bool {
            var cursor = index

            while cursor < value.endIndex, value[cursor] == " " {
                cursor = value.index(after: cursor)
            }

            var length = 0

            while cursor < value.endIndex {
                switch value[cursor] {
                case "=":
                    return length > 0
                case ";", ",", " ", "\t":
                    return false
                default:
                    length += 1
                    cursor = value.index(after: cursor)
                }
            }

            return false
        }
    }
}

extension String {

    fileprivate func trimmingWhitespace() -> String {
        var substring = Substring(self)

        while substring.first == " " || substring.first == "\t" {
            substring.removeFirst()
        }

        while substring.last == " " || substring.last == "\t" {
            substring.removeLast()
        }

        return String(substring)
    }
}
