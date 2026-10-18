//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

/// What a command may do when `CURLTask` is given `allowing:`: the flags that read a file, turn
/// certificate verification off, name a proxy or redirect DNS are refused unless the capability
/// that covers them is there.
struct CURLTaskCapabilitiesTests {

    // MARK: - Refused without the capability

    @Test(arguments: [
        ("curl -F file=@/etc/hosts https://example.com", "-F"),
        ("curl --form file=@/etc/hosts https://example.com", "--form"),
        ("curl -F 'file=@notes.txt;type=text/plain' https://example.com", "-F"),
        ("curl --cacert /tmp/ca.pem https://example.com", "--cacert"),
        ("curl --cert /tmp/client.pem https://example.com", "--cert"),
        ("curl -E /tmp/client.pem https://example.com", "-E"),
        ("curl --key /tmp/client.key https://example.com", "--key"),
        ("curl -k https://example.com", "-k"),
        ("curl --insecure https://example.com", "--insecure"),
        ("curl -x http://proxy.example.com:8080 https://example.com", "-x"),
        ("curl --proxy socks5://proxy.example.com https://example.com", "--proxy"),
        ("curl --resolve example.com:443:127.0.0.1 https://example.com", "--resolve"),
    ])
    func emptyCapabilities_refuseTheFlag(_ command: String, _ flag: String) async {
        // When
        let error = await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parseCommand(command, allowing: [])
        }

        // Then
        #expect(error?.context == .unsupportedFlag)
        #expect(error?.token == flag)
    }

    /// A capability covers its own flags and nothing else.
    @Test(arguments: [
        ("curl -k https://example.com", CURLTask.Capabilities.localFiles),
        ("curl -k https://example.com", .proxy),
        ("curl -x http://proxy.example.com:8080 https://example.com", .disabledTLSVerification),
        ("curl --resolve example.com:443:127.0.0.1 https://example.com", .proxy),
        ("curl --cacert /tmp/ca.pem https://example.com", .dnsOverrides),
        ("curl -F file=@/etc/hosts https://example.com", .disabledTLSVerification),
    ])
    func aCapability_doesNotCoverTheOtherFlags(
        _ command: String,
        _ capabilities: CURLTask.Capabilities
    ) async {
        // When
        let error = await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parseCommand(command, allowing: capabilities)
        }

        // Then
        #expect(error?.context == .unsupportedFlag)
    }

    // MARK: - Allowed with the capability

    @Test(arguments: [
        ("curl --cacert /tmp/ca.pem https://example.com", CURLTask.Capabilities.localFiles),
        ("curl --cert /tmp/client.pem --key /tmp/client.key https://example.com", .localFiles),
        ("curl -k https://example.com", .disabledTLSVerification),
        ("curl -x http://proxy.example.com:8080 https://example.com", .proxy),
        ("curl --resolve example.com:443:127.0.0.1 https://example.com", .dnsOverrides),
    ])
    func theMatchingCapability_allowsTheFlag(
        _ command: String,
        _ capabilities: CURLTask.Capabilities
    ) async throws {
        // When
        let parsed = try await CURLCommandParser.parseCommand(command, allowing: capabilities)

        // Then
        #expect(parsed.sessionConfigurationEdit != nil)
    }

    @Test
    func allCapabilities_allowEveryFlagTogether() async throws {
        // Given
        let command = """
            curl -k -x http://proxy.example.com:8080 --resolve example.com:443:127.0.0.1 \
            --cacert /tmp/ca.pem --cert /tmp/client.pem --key /tmp/client.key https://example.com
            """

        // When
        let parsed = try await CURLCommandParser.parseCommand(command, allowing: .all)

        // Then
        #expect(parsed.sessionConfigurationEdit != nil)
    }

    /// `parseCommand(_:)` and `CURLTask(_:)` are what they were: all of it.
    @Test
    func withoutAllowing_everyFlagIsAllowed() async throws {
        // Given
        let command = "curl -k -x http://proxy.example.com:8080 --cacert /tmp/ca.pem https://example.com"

        // When
        let parsed = try await CURLCommandParser.parseCommand(command)

        // Then
        #expect(parsed.sessionConfigurationEdit != nil)
    }

    // MARK: - What an empty set still allows

    /// Only what touches the machine or the connection needs a capability. A request described
    /// with headers, a body, a form of plain fields, credentials and a redirect policy does not.
    @Test
    func emptyCapabilities_stillAllowAPlainRequest() async throws {
        // Given
        let command = """
            curl -X POST https://example.com/users -H 'Content-Type: application/json' \
            -d '{"name":"John"}' -u user:password -L --max-redirs 3 --compressed -s -o out.json
            """

        // When
        let configuration = try await CURLCommandParser.parseCommand(command, allowing: [])
            .requestConfiguration

        // Then
        #expect(configuration.url == "https://example.com/users")
        #expect(configuration.method == "POST")
    }

    @Test
    func emptyCapabilities_allowAFormOfPlainFields() async throws {
        // Given
        let command = "curl -F name=John -F 'bio=a@b.c' https://example.com/users"

        // When
        let configuration = try await CURLCommandParser.parseCommand(command, allowing: [])
            .requestConfiguration

        // Then
        #expect(configuration.method == "POST")
        #expect(configuration.body != nil)
    }

    // MARK: - Refused before anything is opened

    /// A path that does not exist: with the capability the parse fails opening it, which is not a
    /// `CURLParsingError`; without it the flag is refused first, so the file was never touched.
    @Test
    func aRefusedFile_isNeverOpened() async throws {
        // Given
        let command = "curl -F file=@/nonexistent/request-dl-never-opened.bin https://example.com"

        // When
        let refused = await #expect(throws: CURLParsingError.self) {
            try await CURLCommandParser.parseCommand(command, allowing: [])
        }

        let opened = await #expect(throws: (any Error).self) {
            try await CURLCommandParser.parseCommand(command, allowing: .localFiles)
        }

        // Then
        #expect(refused?.context == .unsupportedFlag)
        #expect(opened != nil)
        #expect(opened is CURLParsingError == false)
    }

    @Test
    func theTask_refusesBeforeAnyNetworkIO() async {
        // Given
        let task = CURLTask("curl -k https://example.com", allowing: [])

        // When / Then
        await #expect(throws: CURLParsingError.self) {
            _ = try await task.result()
        }
    }

    // MARK: - The option set

    @Test
    func capabilities_areDistinctBitsAndAllCoversThem() {
        let each: [CURLTask.Capabilities] = [
            .localFiles, .disabledTLSVerification, .proxy, .dnsOverrides,
        ]

        #expect(Set(each.map(\.rawValue)).count == each.count)

        for capability in each {
            #expect(CURLTask.Capabilities.all.contains(capability))
        }

        #expect(CURLTask.Capabilities.all.rawValue == each.reduce(0) { $0 | $1.rawValue })
        #expect(CURLTask.Capabilities([]).isEmpty)
    }
}
