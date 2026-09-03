//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

/// `CURLCommandParserTests` already covers parsing itself in depth. Most of what's here only has
/// to prove that `CURLTask` actually delegates to `CURLCommandParser` -- a parsing failure has to
/// surface as `CURLParsingError` before any network I/O is attempted, which needs no
/// `LocalServer`.
struct CURLTaskTests {

    @Test
    func unsupportedFlagSurfacesAsCURLParsingErrorBeforeAnyNetworkIO() async throws {
        // Given
        let task = CURLTask("curl -b /path/to/cookies.txt https://example.com")

        // When / Then
        await #expect(throws: CURLParsingError.self) {
            _ = try await task.result()
        }

        do {
            _ = try await task.result()
            Issue.record("Not expecting success")
        } catch let error as CURLParsingError {
            #expect(error.context == .unsupportedFlag)
            #expect(error.token == "-b")
        }
    }

    @Test
    func missingURLSurfacesAsCURLParsingError() async throws {
        // Given
        let task = CURLTask("curl -X POST")

        // When / Then
        do {
            _ = try await task.result()
            Issue.record("Not expecting success")
        } catch let error as CURLParsingError {
            #expect(error.context == .missingURL)
        }
    }

    /// The leading literal `curl` token has to be stripped before flag parsing begins -- if it
    /// weren't, the very first token would be read as an (unsupported) flag instead of being
    /// discarded, which this pins down by checking *which* token the error names.
    @Test
    func leadingCURLTokenIsStripped() async throws {
        // Given
        let task = CURLTask("curl -b /path/to/cookies.txt https://example.com")

        // When / Then
        do {
            _ = try await task.result()
            Issue.record("Not expecting success")
        } catch let error as CURLParsingError {
            #expect(error.token == "-b")
        }
    }

    /// `CURLCommandParserTests` already checks the produced `sessionConfigurationEdit` closure in
    /// isolation. This instead exercises the actual new integration point --
    /// `RawRequestConfigurationProperty.Node.make()` calling that closure on
    /// `Make.sessionConfiguration` during a real `Resolve` walk, which is what `CURLTask.result()`
    /// relies on.
    @Test
    func sessionConfigurationEditFlowsThroughResolve() async throws {
        // Given
        let command = try await CURLCommandParser.parseCommand("curl -k -L https://example.com")

        // When
        let property = RawRequestConfigurationProperty(
            configuration: command.requestConfiguration,
            sessionConfigurationEdit: command.sessionConfigurationEdit
        )

        let (_, make) = try await Resolve(root: property, environment: .init()).partiallyBuild()

        // Then -- `.some(.none)`, not plain `.none`: `certificateVerification` is
        // `NIOSSL.CertificateVerification?`, and that type itself has a `.none` case, so
        // unqualified `.none` here is inferred as `Optional.none` (nil) and would pass whether or
        // not `-k` actually did anything -- this exact ambiguity is what let `-k` silently do
        // nothing at all until it was caught by a real network round trip (see
        // `insecureFlagReachesASelfSignedLocalServer` below).
        #expect(make.sessionConfiguration.secureConnection?.certificateVerification == .some(.none))
        #expect(make.sessionConfiguration.redirectConfiguration == .follow(max: 50, allowCycles: false))
    }

    /// A real, end-to-end network round trip through `CURLTask` -- `-k` reaching `LocalServer`'s
    /// self-signed certificate the same way `-k` would let a real curl reach it. This is the test
    /// that actually caught `-k` doing nothing (see the `.some(.none)` note above): asserting on
    /// `Internals.Session.Configuration` alone, however carefully, never proves the bytes that
    /// reach NIOSSL/CFNetwork are what was intended -- only a live handshake against a genuinely
    /// untrusted certificate does.
    @Test
    func insecureFlagReachesASelfSignedLocalServer() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let result = try await CURLTask("curl -k https://\(localServer.baseURL)\(uri)").result()
        let httpResult = try HTTPResult<String>(result.payload)

        // Then
        #expect(httpResult.response == output)
    }
}
