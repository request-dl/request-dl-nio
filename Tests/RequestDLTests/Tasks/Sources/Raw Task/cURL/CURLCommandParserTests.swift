//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOSSL
import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct CURLCommandParserTests {

    // MARK: - URL

    @Test
    func bareTrailingURL() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse("curl https://example.com/users")

        // Then
        #expect(configuration.url == "https://example.com/users")
        #expect(configuration.method == nil)
    }

    @Test
    func urlFlag() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse("curl --url https://example.com/users?a=1")

        // Then
        #expect(configuration.url == "https://example.com/users?a=1")
    }

    @Test
    func missingURLThrows() async throws {
        // Given / When / Then
        await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parse("curl -X POST")
        }

        do {
            _ = try await CURLCommandParser.parse("curl -X POST")
            Issue.record("Not expecting success")
        } catch let error as CURLParsingError {
            #expect(error.context == .missingURL)
        }
    }

    // MARK: - Method

    @Test
    func requestFlag() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse("curl -X DELETE https://example.com")

        // Then
        #expect(configuration.method == "DELETE")
    }

    @Test
    func longRequestFlag() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse("curl --request PATCH https://example.com")

        // Then
        #expect(configuration.method == "PATCH")
    }

    // MARK: - Headers

    @Test
    func headerFlag() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -H 'Accept: application/json' -H 'X-Trace: abc' https://example.com"
        )

        // Then
        #expect(configuration.headers["Accept"] == ["application/json"])
        #expect(configuration.headers["X-Trace"] == ["abc"])
    }

    @Test
    func headerFlagWithValueContainingColon() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -H 'Referer: http://example.com/from' https://example.com"
        )

        // Then
        #expect(configuration.headers["Referer"] == ["http://example.com/from"])
    }

    @Test
    func malformedHeaderThrows() async throws {
        // Given / When / Then
        await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parse("curl -H 'NoColon' https://example.com")
        }
    }

    // MARK: - Data

    @Test
    func dataFlagDefaultsToPOSTAndFormURLEncodedContentType() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            #"curl -d 'name=John Doe' https://example.com"#
        )

        // Then
        #expect(configuration.method == "POST")
        #expect(configuration.headers["Content-Type"] == ["application/x-www-form-urlencoded"])
        #expect(try await bodyString(configuration) == "name=John Doe")
    }

    @Test
    func dataFlagDoesNotOverrideExplicitContentType() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            #"curl -H 'Content-Type: application/json' -d '{"a":1}' https://example.com"#
        )

        // Then
        #expect(configuration.headers["Content-Type"] == ["application/json"])
        #expect(try await bodyString(configuration) == #"{"a":1}"#)
    }

    @Test
    func repeatedDataFlagsAreJoinedWithAmpersand() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -d 'a=1' -d 'b=2' https://example.com"
        )

        // Then
        #expect(try await bodyString(configuration) == "a=1&b=2")
    }

    @Test
    func dataFlagDoesNotOverrideExplicitMethod() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -X PATCH -d 'a=1' https://example.com"
        )

        // Then
        #expect(configuration.method == "PATCH")
    }

    @Test
    func dataRawAndDataBinaryAreAccepted() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            #"curl --data-raw 'raw' https://example.com"#
        )

        // Then
        #expect(try await bodyString(configuration) == "raw")
    }

    // MARK: - -G / --get

    @Test
    func getFlagMovesDataToQueryString() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -G -d 'a=1' -d 'b=2' https://example.com/search"
        )

        // Then
        #expect(configuration.url == "https://example.com/search?a=1&b=2")
        #expect(configuration.method == nil)
        #expect(configuration.body == nil)
    }

    @Test
    func getFlagAppendsToExistingQueryString() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -G -d 'b=2' https://example.com/search?a=1"
        )

        // Then
        #expect(configuration.url == "https://example.com/search?a=1&b=2")
    }

    // MARK: - -u / --user

    @Test
    func userFlagSetsBasicAuthorizationHeader() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -u john:secret https://example.com"
        )

        // Then
        let expectedToken = Data("john:secret".utf8).base64EncodedString()
        #expect(configuration.headers["Authorization"] == ["Basic \(expectedToken)"])
    }

    @Test
    func malformedUserFlagThrows() async throws {
        // Given / When / Then
        await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parse("curl -u johnsecret https://example.com")
        }
    }

    // MARK: - -F / --form

    @Test
    func formFlagSendsMultipartFieldsAndDefaultsToPOST() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -F 'name=John Doe' -F 'age=30' https://example.com/upload"
        )

        // Then
        #expect(configuration.method == "POST")
        #expect(configuration.headers["Content-Type"]?.first?.hasPrefix("multipart/form-data; boundary=") == true)

        let body = try #require(configuration.body)
        let bodyText = String(decoding: try await drain(body), as: UTF8.self)

        #expect(bodyText.contains(#"name="name""#))
        #expect(bodyText.contains("John Doe"))
        #expect(bodyText.contains(#"name="age""#))
        #expect(bodyText.contains("30"))
    }

    // MARK: - Unsupported flags

    @Test
    func unsupportedFlagThrows() async throws {
        // Given / When / Then
        await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parse("curl -b /path/to/cookies.txt https://example.com")
        }

        do {
            _ = try await CURLCommandParser.parse("curl -b /path/to/cookies.txt https://example.com")
            Issue.record("Not expecting success")
        } catch let error as CURLParsingError {
            #expect(error.context == .unsupportedFlag)
            #expect(error.token == "-b")
        }
    }

    // MARK: - Session-level flags (-L, -k, -x, --resolve, --compressed, --cacert, --cert/-E, --key)

    @Test
    func noSessionLevelFlagsMeansNoSessionConfigurationEdit() async throws {
        // Given / When
        let command = try await CURLCommandParser.parseCommand("curl https://example.com")

        // Then -- a command using only the request-level subset must not touch
        // `Make.sessionConfiguration` in any way, same as before these flags existed.
        #expect(command.sessionConfigurationEdit == nil)
    }

    @Test
    func withoutLocationFlagRedirectsAreExplicitlyDisallowed() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand("curl -k https://example.com")

        // When -- any session-level flag (here just `-k`) makes the edit apply curl's own
        // default for redirects too, not just leave this package's own (opposite) default in
        // place.
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        #expect(sessionConfiguration.redirectConfiguration == .disallow)
    }

    @Test
    func locationFlagFollowsRedirectsUpToFiftyByDefault() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand("curl -L https://example.com")

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        #expect(sessionConfiguration.redirectConfiguration == .follow(max: 50, allowCycles: false))
    }

    @Test
    func locationFlagWithMaxRedirsUsesThatCount() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand(
            "curl -L --max-redirs 3 https://example.com"
        )

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        #expect(sessionConfiguration.redirectConfiguration == .follow(max: 3, allowCycles: false))
    }

    @Test
    func insecureFlagDisablesCertificateVerification() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand("curl -k https://example.com")

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then -- `.some(.none)`, not plain `.none`: the field is `CertificateVerification?`,
        // and `CertificateVerification` itself has a `.none` case, so unqualified `.none` here
        // would be inferred as `Optional.none` (nil) and pass vacuously whether or not the
        // production code actually set anything -- exactly the bug this test exists to catch.
        #expect(sessionConfiguration.secureConnection?.certificateVerification == .some(.none))
    }

    @Test
    func cacertFlagSetsTrustRoots() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand(
            "curl --cacert /path/to/ca.pem https://example.com"
        )

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        #expect(sessionConfiguration.secureConnection?.trustRoots == .file("/path/to/ca.pem"))
    }

    @Test
    func certAndKeyFlagsSetClientIdentity() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand(
            "curl --cert /path/to/client.pem --key /path/to/client.key https://example.com"
        )

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        #expect(sessionConfiguration.secureConnection?.certificateChain == .file("/path/to/client.pem"))
        #expect(
            sessionConfiguration.secureConnection?.privateKey
                == .privateKey(Internals.PrivateKey("/path/to/client.key", format: .pem))
        )
    }

    @Test
    func shortFormCertFlagIsAcceptedAsAnAliasForCert() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand(
            "curl -E /path/to/client.pem https://example.com"
        )

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        #expect(sessionConfiguration.secureConnection?.certificateChain == .file("/path/to/client.pem"))
    }

    @Test
    func proxyFlagWithSchemeCredentialsAndPort() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand(
            "curl -x http://john:secret@proxy.example.com:8080 https://example.com"
        )

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        let proxy = try #require(sessionConfiguration.proxy)
        #expect(proxy.host == "proxy.example.com")
        #expect(proxy.port == 8080)
        #expect(proxy.connectionProtocol == .http)
        #expect(proxy.authorization == .basic(username: "john", password: "secret"))
    }

    @Test
    func proxyFlagWithSocksSchemeAndNoPortDefaultsTo1080() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand(
            "curl -x socks5://proxy.example.com https://example.com"
        )

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        let proxy = try #require(sessionConfiguration.proxy)
        #expect(proxy.host == "proxy.example.com")
        #expect(proxy.port == 1080)
        #expect(proxy.connectionProtocol == .socks)
        #expect(proxy.authorization == nil)
    }

    @Test
    func resolveFlagOverridesDNSForTheGivenHost() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand(
            "curl --resolve example.com:443:127.0.0.1 https://example.com"
        )

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then -- the port is validated but not carried into `dnsOverride`, which has no port
        // dimension.
        #expect(sessionConfiguration.dnsOverride == ["example.com": "127.0.0.1"])
    }

    @Test
    func malformedResolveFlagThrows() async throws {
        // Given / When / Then
        await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parse("curl --resolve example.com https://example.com")
        }
    }

    @Test
    func withoutCompressedFlagDecompressionIsExplicitlyDisabled() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand("curl -k https://example.com")

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        #expect(sessionConfiguration.decompression == .disabled)
    }

    @Test
    func compressedFlagEnablesUnboundedDecompression() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand("curl --compressed https://example.com")

        // When
        var sessionConfiguration = Internals.Session.Configuration()
        let edit = try #require(command.sessionConfigurationEdit)
        edit(&sessionConfiguration)

        // Then
        #expect(sessionConfiguration.decompression == .enabled(.none))
    }

    // MARK: - No-op CLI-output-only flags

    @Test
    func silentAndVerboseFlagsAreIgnored() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -s -S -v -i -# https://example.com"
        )

        // Then
        #expect(configuration.url == "https://example.com")
    }

    @Test
    func longFormNoOpFlagsAreIgnored() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl --silent --show-error --verbose --include --progress-bar https://example.com"
        )

        // Then
        #expect(configuration.url == "https://example.com")
    }

    @Test
    func outputAndWriteOutFlagsConsumeTheirArgumentWithoutAffectingTheRequest() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            "curl -o response.json -w '%{http_code}' https://example.com"
        )

        // Then -- their arguments must not be mistaken for the URL or throw as unsupported.
        #expect(configuration.url == "https://example.com")
    }

    @Test
    func secondBareURLIsRejected() async throws {
        // Given / When / Then
        await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parse("curl https://example.com https://example.org")
        }
    }

    @Test
    func repeatedURLFlagIsRejected() async throws {
        // Given / When / Then -- `--url` used to silently overwrite a previous `url`/`--url`
        // instead of rejecting it like a second bare URL does; both now reject consistently.
        await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parse("curl --url https://example.com --url https://example.org")
        }

        await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parse("curl https://example.com --url https://example.org")
        }
    }

    // MARK: - Quoting

    @Test
    func singleQuotesArePreservedLiterally() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            #"curl -d 'a "quoted" value' https://example.com"#
        )

        // Then
        #expect(try await bodyString(configuration) == #"a "quoted" value"#)
    }

    @Test
    func doubleQuotesInterpretEscapes() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            #"curl -d "a \"quoted\" value" https://example.com"#
        )

        // Then
        #expect(try await bodyString(configuration) == #"a "quoted" value"#)
    }

    @Test
    func ansiCQuotingInterpretsEscapeSequences() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            #"curl -d $'line1\nline2' https://example.com"#
        )

        // Then
        #expect(try await bodyString(configuration) == "line1\nline2")
    }

    @Test
    func lineContinuationsAreJoined() async throws {
        // Given / When
        let configuration = try await CURLCommandParser.parse(
            """
            curl -X POST https://example.com \\
                -H 'Accept: application/json' \\
                -d 'a=1'
            """
        )

        // Then
        #expect(configuration.method == "POST")
        #expect(configuration.headers["Accept"] == ["application/json"])
        #expect(try await bodyString(configuration) == "a=1")
    }

    @Test
    func unterminatedQuoteThrows() async throws {
        // Given / When / Then
        await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parse("curl -d 'unterminated https://example.com")
        }
    }
}

// MARK: - Helpers

extension CURLCommandParserTests {

    private func drain(_ body: RequestBody) async throws -> Data {
        var data = Data()

        for await buffer in body {
            data.append(contentsOf: buffer.readableBytesView)
        }

        return data
    }

    private func bodyString(_ configuration: RequestConfiguration) async throws -> String {
        let body = try #require(configuration.body)
        return String(decoding: try await drain(body), as: UTF8.self)
    }
}
