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

                guard Self.isRule(token) else {
                    throw ParseError.malformed
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

        // MARK: - Private static methods

        /// Whether `token` can be the rule of a list: a name, optionally with a `!` or a leading
        /// `*.`. What is not (the `<!DOCTYPE` of an HTML page a failed download saved in its place)
        /// is reported instead of being read as a list of one rule that protects from nothing.
        private static func isRule(_ token: Substring) -> Bool {
            token.unicodeScalars.allSatisfy { scalar in
                !scalar.isASCII
                    || ("a"..."z").contains(Character(scalar)) || ("A"..."Z").contains(Character(scalar))
                    || ("0"..."9").contains(Character(scalar)) || "-._*!".unicodeScalars.contains(scalar)
            }
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

        /// A line starts with something that cannot be a rule, so the contents are not a Public
        /// Suffix List: an HTML page or an error message saved where the list should be.
        case malformed
    }
}
