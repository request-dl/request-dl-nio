//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Only the two `resolvedDERBytes()` error-path tests, which never touch `NIOSSLCertificate`,
/// stay here. Every other test either calls `Internals.Certificate.build()` (only exists under
/// `canImport(NIOCore)`, returns `[NIOSSLCertificate]`) or compares `resolvedDERBytes()`'s
/// portable output against that same NIOSSL-backed output — see
/// `InternalsCertificateTests+NIO.swift`.
struct InternalsCertificateTests {

    @Test
    func resolvedDERBytes_whenFileDoesNotExist_shouldThrowSecureFileLoadErrorWithPath() async throws {
        try await withTemporaryFileURL("missing.pem", createPath: false) { url in
            // Given
            let path = url.absolutePath(percentEncoded: false)

            // When
            do {
                _ = try Internals.Certificate(path, format: .pem).resolvedDERBytes()
                Issue.record("Not expecting success")
            } catch let error as Internals.SecureFileLoadError {
                // Then
                #expect(error.resource == .certificate)
                #expect(error.path == path)
            }
        }
    }

    @Test
    func resolvedDERBytes_whenFileContentsAreInvalid_shouldThrowSecureFileLoadErrorWithUnderlyingError() async throws {
        try await withTemporaryFileURL("invalid.pem") { url in
            // Given
            try await url.write(Data("not a certificate".utf8))
            let path = url.absolutePath(percentEncoded: false)

            // When
            do {
                _ = try Internals.Certificate(path, format: .pem).resolvedDERBytes()
                Issue.record("Not expecting success")
            } catch let error as Internals.SecureFileLoadError {
                // Then
                #expect(error.resource == .certificate)
                #expect(error.path == path)
            }
        }
    }
}
