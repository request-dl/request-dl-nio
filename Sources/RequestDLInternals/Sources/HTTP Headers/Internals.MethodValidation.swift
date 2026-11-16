//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// The rule a request method must meet to be written on a request line, for both executors.
    ///
    /// A method is a `token` (RFC 9110 §9.1, §5.6.2): at least one `tchar`, and nothing else, no
    /// space and no control character. Neither executor checks it. AsyncHTTPClient turns a method
    /// it does not know into `.RAW(value:)` and `URLSession` takes any `httpMethod`, and both write
    /// it as it is: one carrying `\r\n` ends the request line and the headers, and what follows is
    /// read by the server as a second request. A `GET / HTTP/1.1\r\nX: y\r\n\r\nPOST` went out
    /// that way on both.
    ///
    /// The same failure as ``HeaderValidation``, so which of the two runs a request does not change
    /// whether it is sent.
    package enum MethodValidation {

        // MARK: - Package static methods

        /// - Throws: ``InvalidMethodError`` when `method` is not a token.
        package static func validate(_ method: String) throws {
            guard isValid(method: method) else {
                throw InvalidMethodError()
            }
        }

        /// Whether `method` is a `token`: one or more `tchar`s (RFC 9110 §5.6.2).
        package static func isValid(method: String) -> Bool {
            HeaderValidation.isValid(name: method)
        }
    }

    /// What ``MethodValidation/validate(_:)`` throws.
    ///
    /// Says what was wrong, not with what: the method is whatever a caller put there, and an
    /// error's description ends up in logs.
    package struct InvalidMethodError: Swift.Error, Sendable, Hashable, CustomStringConvertible {

        package var description: String {
            "The request method is not a valid token."
        }

        // MARK: - Inits

        package init() {}
    }
}
