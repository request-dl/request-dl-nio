//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

/// The tokenizer walks the command as `Unicode.Scalar`s: Swift reads `"\r\n"` as a single
/// `Character`, equal to neither `"\r"` nor `"\n"`, so a command whose lines end in CRLF (a
/// Windows text file, an HTTP-style paste) must still split where its lines break, and a `\`
/// before a CRLF is a line continuation.
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

    /// The `$'...'` branch walks scalars too: a raw CRLF in it is data, the `\r\n` escapes make
    /// the same two scalars, and a CRLF after the closing quote still separates tokens.
    @Test
    func tokenize_whenACRLFIsInsideAnANSICLiteral_keepsItInTheToken() throws {
        #expect(try CURLTokenizer.tokenize("curl -d $'a\r\nb'") == ["curl", "-d", "a\r\nb"])
        #expect(try CURLTokenizer.tokenize("curl -d $'a\\r\\nb'") == ["curl", "-d", "a\r\nb"])
        #expect(
            try CURLTokenizer.tokenize("curl -d $'a\\r\\nb'\r\nhttps://example.com")
                == ["curl", "-d", "a\r\nb", "https://example.com"]
        )
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

    /// A closing quote followed by a combining mark is one `Character` that doesn't equal the
    /// quote, but it still closes the quoted string.
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

    // MARK: - ANSI-C escapes and unfinished input

    @Test
    func tokenize_whenAnANSICLiteralHasTheOtherEscapes_decodesThem() throws {
        // Tab, backslash, single and double quote, and NUL.
        let tokens = try CURLTokenizer.tokenize(#"curl -d $'a\tb\\c\'d\"e\0f'"#)

        #expect(tokens == ["curl", "-d", "a\tb\\c'd\"e\0f"])
    }

    @Test
    func tokenize_whenAnANSICLiteralHasAMalformedHexEscape_keepsTheLetterAndTheRest() throws {
        let tokens = try CURLTokenizer.tokenize(#"curl -d $'a\xZb'"#)

        #expect(tokens == ["curl", "-d", "axZb"])
    }

    @Test
    func tokenize_whenADoubleQuotedStringHasAnEscape_keepsTheEscapedCharacter() throws {
        let tokens = try CURLTokenizer.tokenize(#"curl -d "a\"b""#)

        #expect(tokens == ["curl", "-d", "a\"b"])
    }

    @Test
    func tokenize_whenAnANSICLiteralHasHexBytes_decodesThemTogetherAsUTF8() throws {
        // `\xc3\xa9` is the two bytes of "é".
        let tokens = try CURLTokenizer.tokenize(#"curl -d $'caf\xc3\xa9'"#)

        #expect(tokens == ["curl", "-d", "caf\u{e9}"])
    }

    @Test(arguments: ["curl -d $'abc", "curl -d 'abc", "curl -d \"abc"])
    func tokenize_whenAQuoteIsNeverClosed_throws(_ command: String) {
        #expect(throws: CURLParsingError.self) {
            try CURLTokenizer.tokenize(command)
        }
    }

    @Test
    func tokenize_whenTheCommandEndsInABackslash_throws() {
        #expect(throws: CURLParsingError.self) {
            try CURLTokenizer.tokenize("curl https://example.com\\")
        }
    }
}
