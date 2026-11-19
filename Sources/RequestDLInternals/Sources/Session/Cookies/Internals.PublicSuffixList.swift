//
// See LICENSE for this package's licensing information.
//

import Foundation

extension Internals {

    /// The rules of a [Public Suffix List](https://publicsuffix.org) in the `.dat` format, which a
    /// cookie jar consults to refuse a `Domain` under which unrelated parties register names.
    ///
    /// Immutable once built, so one list is shared by every request that uses it, and parsed once.
    package struct PublicSuffixList: Sendable {

        // MARK: - Private properties

        private let exact: Set<String>
        private let wildcards: Set<String>
        private let exceptions: Set<String>

        // MARK: - Inits

        /// - Throws: ``Internals/PublicSuffixList/ParseError/noRules`` when `contents` holds none.
        package init(_ contents: String) throws {
            var exact = Set<String>()
            var wildcards = Set<String>()
            var exceptions = Set<String>()

            for line in contents.split(whereSeparator: \.isNewline) {
                // A rule is the first whitespace-delimited token of a line; `//` starts a comment.
                guard
                    let token = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
                    !token.hasPrefix("//")
                else {
                    continue
                }

                let rule = Internals.HostName.ascii(String(token))

                if rule.hasPrefix("!") {
                    exceptions.insert(String(rule.dropFirst()))
                } else if rule.hasPrefix("*.") {
                    wildcards.insert(String(rule.dropFirst(2)))
                } else {
                    exact.insert(rule)
                }
            }

            guard !exact.isEmpty || !wildcards.isEmpty else {
                throw ParseError.noRules
            }

            self.exact = exact
            self.wildcards = wildcards
            self.exceptions = exceptions
        }

        // MARK: - Internal methods

        /// Whether `domain` is, itself, a public suffix: a name nobody may set a cookie for.
        package func isPublicSuffix(_ domain: String) -> Bool {
            let domain = Internals.HostName.ascii(domain)

            if exceptions.contains(domain) {
                return false
            }

            if exact.contains(domain) {
                return true
            }

            guard let dot = domain.firstIndex(of: ".") else {
                return false
            }

            return wildcards.contains(String(domain[domain.index(after: dot)...]))
        }
    }
}

extension Internals.PublicSuffixList {

    package enum ParseError: Error, Sendable, Equatable {

        /// The contents hold no rule, so they are not a Public Suffix List.
        case noRules
    }
}
