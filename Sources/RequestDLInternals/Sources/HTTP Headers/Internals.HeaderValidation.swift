//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// The header rules AsyncHTTPClient enforces on every request it sends, for the executor that
    /// does not have it.
    ///
    /// `.nio` rejects a request whose header name is not a token (RFC 9110 §5.1) or whose value
    /// carries a control character other than HTAB (RFC 9110 §5.5). `URLSession` checks
    /// neither: a name of `X-A: injected` goes out as the line `X-A: injected: v`, and a NUL in a
    /// value goes out as a NUL, so the same request that fails on one executor reaches the server
    /// on the other, with a header the caller never wrote.
    ///
    /// This is the same check, with the same error, so which of the two runs a request does not
    /// change whether it is sent. The error is ``InvalidHeaderError``, on every platform: it names
    /// what was wrong and never a header value, since a value is as likely to be a credential as
    /// anything else, and AsyncHTTPClient's own `HTTPClientError.invalidHeaderFieldValues` carries
    /// every offending value and prints it. The predicates are AsyncHTTPClient's own (see
    /// `RequestValidation.swift` there), not a stricter reading of the RFC, except for the empty
    /// name that ``isValid(name:)`` refuses: tightening them any further here would make
    /// `.urlSession` refuse what `.nio` sends. `.nio` applies this check too, before AsyncHTTPClient's.
    ///
    /// - Important: Not a limit on what a value may *say*. Bytes from `0x80` up are allowed,
    /// since a non-ASCII value (`José`, `日本語`) is legitimate on `.nio`, which sends it as UTF-8.
    /// `URLSession` does not: it sends each character in Latin-1 and cuts the value at the first
    /// one that has no Latin-1 form, which this does not (and cannot, without refusing values
    /// `.nio` sends) detect.
    package enum HeaderValidation {

        // MARK: - Package static methods

        /// - Throws: ``InvalidHeaderError``, for the names when any is not a token and otherwise for
        /// the values, as AsyncHTTPClient reports them, but without the offending values.
        package static func validate<Headers: Sequence>(
            _ headers: Headers
        ) throws where Headers.Element == (name: String, value: String) {
            let invalidNames = headers.filter { !isValid(name: $0.name) }

            guard invalidNames.isEmpty else {
                throw InvalidHeaderError(.name, count: invalidNames.count)
            }

            // The name of a header whose value is invalid is a token, so it is safe to report and
            // says which one to look at; the value is not.
            let invalidValues = headers.filter { !isValid(value: $0.value) }

            guard invalidValues.isEmpty else {
                throw InvalidHeaderError(.value, count: invalidValues.count, headerNames: invalidValues.map(\.name))
            }
        }

        /// Whether `name` is a `token`: one or more `tchar`s (RFC 9110 §5.6.2).
        ///
        /// AsyncHTTPClient's own predicate, but for an empty name, which it lets through and a token
        /// (at least one `tchar`) is not: it goes out as the line `: value`.
        package static func isValid(name: String) -> Bool {
            guard !name.isEmpty else {
                return false
            }

            return name.utf8.allSatisfy { byte in
                switch byte {
                case UInt8(ascii: "a")...UInt8(ascii: "z"),
                    UInt8(ascii: "A")...UInt8(ascii: "Z"),
                    UInt8(ascii: "0")...UInt8(ascii: "9"),
                    UInt8(ascii: "!"), UInt8(ascii: "#"), UInt8(ascii: "$"), UInt8(ascii: "%"),
                    UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "*"), UInt8(ascii: "+"),
                    UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "^"), UInt8(ascii: "_"),
                    UInt8(ascii: "`"), UInt8(ascii: "|"), UInt8(ascii: "~"):
                    return true
                default:
                    return false
                }
            }
        }

        /// Whether `value` has no ASCII control character (NUL, CR, LF included) but HTAB.
        package static func isValid(value: String) -> Bool {
            value.utf8.allSatisfy { byte in
                switch byte {
                case UInt8(ascii: "\t"):
                    return true
                case 0...0x1F, 0x7F:
                    return false
                default:
                    return true
                }
            }
        }
    }

    /// What ``HeaderValidation/validate(_:)`` throws.
    ///
    /// Says what was wrong, not with what: a rejected value is as likely to be a credential as
    /// anything else, and an error's description ends up in logs. For a value it also names the
    /// headers that carried one, which are valid tokens; a rejected name is only counted.
    package struct InvalidHeaderError: Swift.Error, Sendable, Hashable, CustomStringConvertible {

        // MARK: - Inner types

        package enum Kind: Sendable, Hashable {
            case name
            case value
        }

        // MARK: - Package properties

        package let kind: Kind
        package let count: Int
        /// The names of the headers whose value was rejected. Empty for ``Kind/name``.
        package let headerNames: [String]

        package var description: String {
            switch kind {
            case .name:
                return "\(count) header field name(s) are not valid tokens."
            case .value:
                let names = headerNames.isEmpty ? "" : " (\(headerNames.joined(separator: ", ")))"
                return "\(count) header field value(s) contain a control character\(names)."
            }
        }

        // MARK: - Inits

        package init(_ kind: Kind, count: Int, headerNames: [String] = []) {
            self.kind = kind
            self.count = count
            self.headerNames = headerNames
        }
    }
}
