//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsMethodValidationTests {

    @Test(arguments: ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "PROPFIND", "M-SEARCH", "get", "A1"])
    func validate_whenMethodIsAToken_accepts(method: String) throws {
        try Internals.MethodValidation.validate(method)
    }

    @Test(arguments: [
        "",
        "GET / HTTP/1.1\r\nX: y\r\n\r\nPOST",
        "GET\r\n",
        "GET\n",
        "GE T",
        "GET\t",
        "G\u{0}ET",
        "GET:",
        "GET/",
        "G(T",
        "GÉT",
        "GET\u{7F}",
    ])
    func validate_whenMethodIsNotAToken_rejects(method: String) {
        #expect(!Internals.MethodValidation.isValid(method: method))

        #expect(throws: Internals.InvalidMethodError.self) {
            try Internals.MethodValidation.validate(method)
        }
    }

    /// The method is whatever a caller put there: it stays out of the error, which ends up in logs.
    @Test
    func error_doesNotRepeatTheMethod() {
        let error = Internals.InvalidMethodError()

        #expect(!error.description.contains("GET"))
    }
}
