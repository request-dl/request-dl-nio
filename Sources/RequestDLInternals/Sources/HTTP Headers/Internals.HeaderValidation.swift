//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

extension Internals {

    /// The header rules AsyncHTTPClient enforces on every request it sends, for the executor that
    /// does not have it.
    ///
    /// `.nio` rejects a request whose header name is not a token (RFC 9110 §5.1) or whose value
    /// carries a control character other than HTAB (RFC 9110 §5.5), failing it with
    /// `HTTPClientError.invalidHeaderFieldNames`/`.invalidHeaderFieldValues`. `URLSession` checks
    /// neither: a name of `X-A: injected` goes out as the line `X-A: injected: v`, and a NUL in a
    /// value goes out as a NUL, so the same request that fails on one executor reaches the server
    /// on the other, with a header the caller never wrote.
    ///
    /// This is the same check, with the same error, so which of the two runs a request does not
    /// change whether it is sent. The predicates are AsyncHTTPClient's own, byte for byte (see
    /// `RequestValidation.swift` there), not a stricter reading of the RFC: tightening them here
    /// would make `.urlSession` refuse what `.nio` sends.
    ///
    /// - Important: Not a limit on what a value may *say*. Bytes from `0x80` up are allowed,
    /// since a non-ASCII value (`José`, `日本語`) is legitimate on `.nio`, which sends it as UTF-8.
    /// `URLSession` does not: it sends each character in Latin-1 and cuts the value at the first
    /// one that has no Latin-1 form, which this does not (and cannot, without refusing values
    /// `.nio` sends) detect.
    package enum HeaderValidation {

        // MARK: - Package static methods

        /// - Throws: `HTTPClientError.invalidHeaderFieldNames`/`.invalidHeaderFieldValues` (every
        /// offender, names first, as AsyncHTTPClient reports them) where AsyncHTTPClient is
        /// available, ``InvalidHeaderError`` where it is not.
        package static func validate<Headers: Sequence>(
            _ headers: Headers
        ) throws where Headers.Element == (name: String, value: String) {
            let invalidNames = headers.compactMap { isValid(name: $0.name) ? nil : $0.name }

            guard invalidNames.isEmpty else {
                #if canImport(NIOCore)
                throw HTTPClientError.invalidHeaderFieldNames(invalidNames)
                #else
                throw InvalidHeaderError(.name, count: invalidNames.count)
                #endif
            }

            let invalidValues = headers.compactMap { isValid(value: $0.value) ? nil : $0.value }

            guard invalidValues.isEmpty else {
                #if canImport(NIOCore)
                throw HTTPClientError.invalidHeaderFieldValues(invalidValues)
                #else
                throw InvalidHeaderError(.value, count: invalidValues.count)
                #endif
            }
        }

        /// Whether `name` is a `token`: made of `tchar`s (RFC 9110 §5.6.2), as AsyncHTTPClient has it, which
        /// also lets an empty one through.
        package static func isValid(name: String) -> Bool {
            name.utf8.allSatisfy { byte in
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

    /// What ``HeaderValidation/validate(_:)`` throws where AsyncHTTPClient, whose own errors
    /// these are on `.nio`, is not part of the build.
    ///
    /// Says what was wrong, not with what: a rejected value is as likely to be a credential as
    /// anything else, and an error's description ends up in logs.
    package struct InvalidHeaderError: Swift.Error, Sendable, Hashable, CustomStringConvertible {

        // MARK: - Inner types

        package enum Kind: Sendable, Hashable {
            case name
            case value
        }

        // MARK: - Package properties

        package let kind: Kind
        package let count: Int

        package var description: String {
            switch kind {
            case .name:
                return "\(count) header field name(s) are not valid tokens."
            case .value:
                return "\(count) header field value(s) contain a control character."
            }
        }

        // MARK: - Inits

        package init(_ kind: Kind, count: Int) {
            self.kind = kind
            self.count = count
        }
    }
}
