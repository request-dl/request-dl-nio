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
/// portable output against that same NIOSSL-backed output (see
/// `InternalsCertificateTests+NIO.swift`).
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

    // MARK: - TRUSTED CERTIFICATE

    private func trustedCertificatePEM(_ payload: [UInt8]) -> Data {
        let base64 = Data(payload).base64EncodedString()

        return Data("-----BEGIN TRUSTED CERTIFICATE-----\n\(base64)\n-----END TRUSTED CERTIFICATE-----\n".utf8)
    }

    /// A `SEQUENCE` with a three-byte content, then the trust block OpenSSL appends.
    @Test
    func resolvedPEMCertificateDERBytes_whenTrustedCertificate_dropsTheTrustBlock() throws {
        let certificate: [UInt8] = [0x30, 0x03, 0x01, 0x01, 0xFF]
        let pem = trustedCertificatePEM(certificate + [0x30, 0x00])

        let resolved = try Internals.Certificate.resolvedPEMCertificateDERBytes(of: pem)

        #expect(resolved == [Data(certificate)])
    }

    @Test
    func resolvedPEMCertificateDERBytes_whenTrustedCertificateDoesNotStartWithASequence_isKeptAsItIs() throws {
        let payload: [UInt8] = [0x31, 0x84, 0x7F, 0xFF, 0xFF, 0xFF]

        let resolved = try Internals.Certificate.resolvedPEMCertificateDERBytes(of: trustedCertificatePEM(payload))

        #expect(resolved == [Data(payload)])
    }

    /// A length of four bytes near `Int32.max` made `headerCount + length` overflow `Int` on a
    /// 32-bit platform (watchOS arm64_32), which traps. It is compared with what the DER holds
    /// without that arithmetic now, and is a corrupt certificate, not a crash, on every platform.
    @Test(
        arguments: [
            [0x30, 0x84, 0x7F, 0xFF, 0xFF, 0xFF],
            [0x30, 0x84, 0x7F, 0xFF, 0xFF, 0xFA, 0x00],
            [0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF],
            [0x30, 0x84, 0x80, 0x00, 0x00, 0x00, 0x01],
            [0x30, 0x84, 0x00, 0x00, 0x01, 0x00, 0x01],
            [0x30, 0x82, 0x01, 0x00, 0x01],
            [0x30, 0x05, 0x01],
        ] as [[UInt8]]
    )
    func resolvedPEMCertificateDERBytes_whenTrustedCertificateDeclaresMoreThanItHolds_throws(
        _ payload: [UInt8]
    ) throws {
        #expect(throws: Internals.MalformedPEMError.self) {
            try Internals.Certificate.resolvedPEMCertificateDERBytes(of: trustedCertificatePEM(payload))
        }
    }
}
