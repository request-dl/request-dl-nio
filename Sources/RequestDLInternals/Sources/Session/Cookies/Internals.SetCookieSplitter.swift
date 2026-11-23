//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Splits a `Set-Cookie` value that a transport folded several headers into.
    ///
    /// `HTTPURLResponse.allHeaderFields` joins repeated headers with `", "`, and the `Expires`
    /// attribute has a comma of its own (`Wed, 01 Jan 2031`), so a plain split on commas cuts
    /// cookies in the middle of their date. A cookie starts here only after a comma **and a
    /// space**, and only when what follows looks like `name=`: a token with no space, `;` or `,`
    /// before the first `=`.
    ///
    /// RFC 6265 section 3 says `Set-Cookie` headers are not to be folded, because a comma is part
    /// of the header's own grammar: a comma is not what separates two cookies. The `.nio` executor
    /// gets each header apart, and keeps `a=1,b=2` as one cookie. The transport that folds joins
    /// with a comma and a space, so requiring the space keeps that value as one cookie here too.
    /// What cannot be told apart once folded is a value that holds a comma, a space and `name=`
    /// (`a=1, b=2` sent as one header): that is split here and not under `.nio`.
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

            // What the transport joins with is a comma and a space: a comma straight before a
            // token is part of a value.
            guard cursor < value.endIndex, value[cursor] == " " else {
                return false
            }

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
