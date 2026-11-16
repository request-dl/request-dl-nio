//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

struct InternalsHeaderValidationTests {

    // MARK: - Names

    @Test(arguments: ["Accept", "X-Request-Id", "x_custom.header", "X-A~1", "!#$%&'*+-.^_`|~", "A1"])
    func validate_whenNameIsAToken_accepts(name: String) throws {
        try Internals.HeaderValidation.validate([(name: name, value: "v")])
    }

    /// `X-A: injected` is the case that matters: the colon ends the name on the wire, so the
    /// header the server reads is `X-A` with the value `injected: v`.
    @Test(arguments: ["X-A: injected", "X A", "X-A\t", "X-Ä", "(X)", "X/A", "X@A", "X=A", "[X]", "X,A", "X;A"])
    func validate_whenNameIsNotAToken_rejects(name: String) {
        #expect(throws: (any Error).self) {
            try Internals.HeaderValidation.validate([(name: name, value: "v")])
        }
    }

    /// A token has at least one `tchar`: an empty name goes out as the line `: value`.
    @Test
    func validate_whenNameIsEmpty_rejects() {
        #expect(!Internals.HeaderValidation.isValid(name: ""))

        #expect(throws: (any Error).self) {
            try Internals.HeaderValidation.validate([(name: "", value: "v")])
        }
    }

    // MARK: - Values

    /// Non-ASCII is legitimate: `.nio` sends it as UTF-8, so it must not be refused here.
    @Test(arguments: ["", "plain", "a b", "a\tb", "José", "日本語", "a\u{0085}b", "a\u{2028}b", "hi 😀", "\u{00A0}"])
    func validate_whenValueHasNoASCIIControl_accepts(value: String) throws {
        try Internals.HeaderValidation.validate([(name: "X-A", value: value)])
    }

    @Test(arguments: ["a\u{0000}b", "a\u{0001}b", "a\u{0008}b", "a\u{000B}b", "a\u{001F}b", "a\u{007F}b", "\r", "\n"])
    func validate_whenValueHasAnASCIIControl_rejects(value: String) {
        #expect(throws: (any Error).self) {
            try Internals.HeaderValidation.validate([(name: "X-A", value: value)])
        }
    }

    // MARK: - Error

    /// The error AsyncHTTPClient fails a `.nio` request with for the same header, so a caller
    /// catching one catches the other.
    #if canImport(NIOCore)
    @Test
    func validate_whenNameIsInvalid_throwsTheErrorAsyncHTTPClientDoes() {
        #expect(throws: HTTPClientError.invalidHeaderFieldNames(["X-A: injected"])) {
            try Internals.HeaderValidation.validate([(name: "X-A: injected", value: "v")])
        }
    }

    @Test
    func validate_whenValueIsInvalid_throwsTheErrorAsyncHTTPClientDoes() {
        #expect(throws: HTTPClientError.invalidHeaderFieldValues(["a\u{0000}b"])) {
            try Internals.HeaderValidation.validate([(name: "X-A", value: "a\u{0000}b")])
        }
    }

    @Test
    func validate_whenNameAndValueAreInvalid_reportsTheNamesFirstAndEveryOffender() {
        #expect(throws: HTTPClientError.invalidHeaderFieldNames(["X A", "X:B"])) {
            try Internals.HeaderValidation.validate([
                (name: "X A", value: "a\u{0000}b"),
                (name: "X-OK", value: "ok"),
                (name: "X:B", value: "v"),
            ])
        }
    }
    #else
    @Test
    func validate_whenNameIsInvalid_throwsInvalidHeaderError() {
        #expect(throws: Internals.InvalidHeaderError(.name, count: 1)) {
            try Internals.HeaderValidation.validate([(name: "X-A: injected", value: "v")])
        }
    }

    @Test
    func validate_whenValueIsInvalid_throwsInvalidHeaderError() {
        #expect(throws: Internals.InvalidHeaderError(.value, count: 1)) {
            try Internals.HeaderValidation.validate([(name: "X-A", value: "a\u{0000}b")])
        }
    }
    #endif
}
