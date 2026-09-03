//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// `CURLCommandParserTests` already covers parsing itself in depth. This only has to prove that
/// `CURLTask` actually delegates to `CURLCommandParser` -- a parsing failure has to surface as
/// `CURLParsingError` before any network I/O is attempted, which needs no `LocalServer`. (A real
/// network round trip isn't tested here: `CURLTask` has no way to configure trust roots, so
/// there's no local, self-signed-certificate server it could reach -- matching the documented v1
/// scope, which leaves TLS/proxy flags out entirely.)
struct CURLTaskTests {

    @Test
    func unsupportedFlagSurfacesAsCURLParsingErrorBeforeAnyNetworkIO() async throws {
        // Given
        let task = CURLTask("curl -k https://example.com")

        // When / Then
        await #expect(throws: CURLParsingError.self) {
            _ = try await task.result()
        }

        do {
            _ = try await task.result()
            Issue.record("Not expecting success")
        } catch let error as CURLParsingError {
            #expect(error.context == .unsupportedFlag)
            #expect(error.token == "-k")
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
        let task = CURLTask("curl -k https://example.com")

        // When / Then
        do {
            _ = try await task.result()
            Issue.record("Not expecting success")
        } catch let error as CURLParsingError {
            #expect(error.token == "-k")
        }
    }
}
