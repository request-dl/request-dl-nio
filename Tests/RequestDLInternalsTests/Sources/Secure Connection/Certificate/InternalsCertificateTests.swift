//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsCertificateTests {

    @Test
    func certificate_whenPEMBytes_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let data = try Data(contentsOf: certificates.certificateURL)

        // When
        let resolved = try Internals.Certificate(Array(data), format: .pem).build()

        // Then
        let expectedCertificates: [NIOSSLCertificate] = try [
            .init(bytes: Array(data), format: .pem)
        ]
        #expect(resolved == expectedCertificates)
    }

    @Test
    func certificate_whenDERBytes_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()
        let data = try Data(contentsOf: certificates.certificateURL)

        // When
        let resolved = try Internals.Certificate(Array(data), format: .der).build()

        // Then
        let expectedCertificates: [NIOSSLCertificate] = try [
            .init(bytes: Array(data), format: .der)
        ]
        #expect(resolved == expectedCertificates)
    }

    @Test
    func certificate_whenPEMFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let path = certificates.certificateURL.path

        // When
        let resolved = try Internals.Certificate(path, format: .pem).build()

        // Then
        let expectedCertificates = try NIOSSLCertificate.fromPEMFile(path)
        #expect(resolved == expectedCertificates)
    }

    @Test
    func certificate_whenDERFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()
        let path = certificates.certificateURL.path

        // When
        let resolved = try Internals.Certificate(path, format: .der).build()

        // Then
        let expectedCertificates = try [NIOSSLCertificate.fromDERFile(path)]
        #expect(resolved == expectedCertificates)
    }

    @Test
    func certificate_whenFileDoesNotExist_shouldThrowSecureFileLoadErrorWithPath() async throws {
        try await withTemporaryFileURL("missing.pem", createPath: false) { url in
            // Given
            let path = url.absolutePath(percentEncoded: false)

            // When
            do {
                _ = try Internals.Certificate(path, format: .pem).build()
                Issue.record("Not expecting success")
            } catch let error as Internals.SecureFileLoadError {
                // Then
                // The finer-grained classification (relative-path detection, "can't open" vs.
                // "invalid contents") lives entirely in `RequestDL.SecureFileError.init`, built
                // from exactly this `resource`/`path`/`underlying` triple; see
                // `SecureFileErrorTests` in `RequestDLTests` for that coverage.
                #expect(error.resource == .certificate)
                #expect(error.path == path)
            }
        }
    }

    @Test
    func certificate_whenFileContentsAreInvalid_shouldThrowSecureFileLoadErrorWithUnderlyingError() async throws {
        try await withTemporaryFileURL("invalid.pem") { url in
            // Given
            try await url.write(Data("not a certificate".utf8))
            let path = url.absolutePath(percentEncoded: false)

            // When
            do {
                _ = try Internals.Certificate(path, format: .pem).build()
                Issue.record("Not expecting success")
            } catch let error as Internals.SecureFileLoadError {
                // Then
                #expect(error.resource == .certificate)
                #expect(error.path == path)
            }
        }
    }

    // MARK: - resolvedDERBytes (portable, no NIOSSL)

    /// Not just type-checked: `resolvedDERBytes()` (SwiftASN1-backed) must produce byte-for-byte
    /// identical DER to `build()` (NIOSSL-backed) for the exact same input, since
    /// `RawBytesIdentityBuilder`/`ServerTrustPolicy` switch between the two depending on whether
    /// NIOCore is available. A silent mismatch here would mean a different certificate gets
    /// pinned/trusted depending on which build this runs in.
    @Test
    func resolvedDERBytes_whenPEMBytes_matchesNIOSSLBuildOutput() async throws {
        // Given
        let certificates = Certificates().client()
        let data = try Data(contentsOf: certificates.certificateURL)

        // When
        let resolved = try Internals.Certificate(Array(data), format: .pem).resolvedDERBytes()

        // Then
        let expected = try Internals.Certificate(Array(data), format: .pem).build().map {
            Data(try $0.toDERBytes())
        }
        #expect(resolved == expected)
    }

    @Test
    func resolvedDERBytes_whenDERBytes_matchesNIOSSLBuildOutput() async throws {
        // Given
        let certificates = Certificates(.der).client()
        let data = try Data(contentsOf: certificates.certificateURL)

        // When
        let resolved = try Internals.Certificate(Array(data), format: .der).resolvedDERBytes()

        // Then
        let expected = try Internals.Certificate(Array(data), format: .der).build().map {
            Data(try $0.toDERBytes())
        }
        #expect(resolved == expected)
    }

    @Test
    func resolvedDERBytes_whenPEMFile_matchesNIOSSLBuildOutput() async throws {
        // Given
        let certificates = Certificates().client()
        let path = certificates.certificateURL.path

        // When
        let resolved = try Internals.Certificate(path, format: .pem).resolvedDERBytes()

        // Then
        let expected = try NIOSSLCertificate.fromPEMFile(path).map { Data(try $0.toDERBytes()) }
        #expect(resolved == expected)
    }

    @Test
    func resolvedDERBytes_whenDERFile_matchesNIOSSLBuildOutput() async throws {
        // Given
        let certificates = Certificates(.der).client()
        let path = certificates.certificateURL.path

        // When
        let resolved = try Internals.Certificate(path, format: .der).resolvedDERBytes()

        // Then
        let expected = try [Data(NIOSSLCertificate.fromDERFile(path).toDERBytes())]
        #expect(resolved == expected)
    }

    @Test
    func resolvedDERBytes_whenPEMBundleFileHasMultipleCertificates_returnsOneEntryPerCertificate() async throws {
        // Given: the client and server fixtures concatenated into one PEM bundle file, mirroring
        // a leaf-plus-intermediate chain file. `.file`, not `.bytes`. See the asymmetry test
        // right below for why that distinction matters here.
        try await withTemporaryFileURL("bundle.pem") { url in
            let client = Certificates().client()
            let server = Certificates().server()
            let clientData = try Data(contentsOf: client.certificateURL)
            let serverData = try Data(contentsOf: server.certificateURL)
            try await url.write(clientData + serverData)
            let path = url.absolutePath(percentEncoded: false)

            // When
            let resolved = try Internals.Certificate(path, format: .pem).resolvedDERBytes()

            // Then
            let expected = try NIOSSLCertificate.fromPEMFile(path).map { Data(try $0.toDERBytes()) }
            #expect(resolved.count == 2)
            #expect(resolved == expected)
        }
    }

    /// `Certificate.build()`'s `.bytes` case calls `NIOSSLCertificate.fromPEMBytes`, so a
    /// multi-certificate PEM bundle sourced from `.bytes` reads every certificate, matching
    /// `.file`'s own behavior. Confirmed here, not assumed.
    @Test
    func resolvedDERBytes_whenPEMBundleBytesHasMultipleCertificates_returnsOneEntryPerCertificate()
        async throws
    {
        // Given
        let client = Certificates().client()
        let server = Certificates().server()
        let clientData = try Data(contentsOf: client.certificateURL)
        let serverData = try Data(contentsOf: server.certificateURL)
        let bundle = clientData + serverData

        // When
        let resolved = try Internals.Certificate(Array(bundle), format: .pem).resolvedDERBytes()

        // Then
        let expected = try Internals.Certificate(Array(bundle), format: .pem).build().map {
            Data(try $0.toDERBytes())
        }
        #expect(resolved.count == 2)
        #expect(resolved == expected)
    }

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
