//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

/// Regression tests (audit finding N11): the tokenizer walked the command as `Character`s, and
/// Swift reads `"\r\n"` as a single `Character`, equal to neither `"\r"` nor `"\n"`. A command
/// whose lines end in CRLF (a Windows text file, an HTTP-style paste) was not split where its
/// lines break, and a `\` before a CRLF was not a line continuation.
struct CURLTokenizerTests {

    @Test
    func tokenize_whenLinesEndInLF_splitsThem() throws {
        #expect(
            try CURLTokenizer.tokenize("curl\nhttps://example.com\n-X\nPOST") == [
                "curl", "https://example.com", "-X", "POST",
            ]
        )
    }

    @Test
    func tokenize_whenLinesEndInCRLF_splitsThemTheSameWay() throws {
        let tokens = try CURLTokenizer.tokenize("curl\r\nhttps://example.com\r\n-X\r\nPOST")

        #expect(tokens == ["curl", "https://example.com", "-X", "POST"])
    }

    @Test
    func tokenize_whenAContinuationIsFollowedByCRLF_joinsTheLines() throws {
        let tokens = try CURLTokenizer.tokenize("curl \\\r\n  -X POST \\\r\n  https://example.com")

        #expect(tokens == ["curl", "-X", "POST", "https://example.com"])
    }

    @Test
    func tokenize_whenAContinuationIsFollowedByLF_joinsTheLines() throws {
        let tokens = try CURLTokenizer.tokenize("curl \\\n  -X POST \\\n  https://example.com")

        #expect(tokens == ["curl", "-X", "POST", "https://example.com"])
    }

    /// Inside quotes a line break is data, and a shell hands it on byte for byte.
    @Test
    func tokenize_whenACRLFIsInsideQuotes_keepsItInTheToken() throws {
        #expect(try CURLTokenizer.tokenize("curl -d 'a\r\nb'") == ["curl", "-d", "a\r\nb"])
        #expect(try CURLTokenizer.tokenize("curl -d \"a\r\nb\"") == ["curl", "-d", "a\r\nb"])
    }

    @Test
    func tokenize_whenALoneCarriageReturnSeparatesTokens_splitsThem() throws {
        #expect(try CURLTokenizer.tokenize("curl\rhttps://example.com") == ["curl", "https://example.com"])
    }

    /// A backslash before a lone carriage return is not a continuation, and escapes it.
    @Test
    func tokenize_whenABackslashPrecedesALoneCarriageReturn_escapesIt() throws {
        #expect(try CURLTokenizer.tokenize("a\\\rb") == ["a\rb"])
    }

    // MARK: - The same family: a delimiter followed by a combining mark

    /// A closing quote followed by a combining mark is one `Character` and no longer equals the
    /// quote, so the quoted string ran on to the end of the command and "ended unterminated".
    @Test
    func tokenize_whenAQuoteIsFollowedByACombiningMark_stillClosesIt() throws {
        let tokens = try CURLTokenizer.tokenize("curl -H 'X: a'\u{301} https://example.com")

        #expect(tokens == ["curl", "-H", "X: a\u{301}", "https://example.com"])
    }

    @Test
    func tokenize_whenASpaceIsFollowedByACombiningMark_stillSeparatesTokens() throws {
        let tokens = try CURLTokenizer.tokenize("curl \u{301}x")

        #expect(tokens == ["curl", "\u{301}x"])
    }
}
