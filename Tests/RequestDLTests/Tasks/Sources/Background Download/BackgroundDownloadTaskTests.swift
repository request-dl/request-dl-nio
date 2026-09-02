//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Crypto
import NIOSSL
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

/// Only covers `result()`'s validation guard -- the part that runs and throws (or doesn't) before
/// ever reaching `BackgroundDownloads.Session.shared.schedule(...)`. Actually scheduling a
/// download would start a real `URLSessionConfiguration.background` session from this bare
/// SwiftPM test harness, an unsigned CLI process with none of the entitlements a real app target
/// has; that path is not exercised here, the same way this suite's mTLS tests don't exercise a
/// real Keychain round trip either. A file-backed client certificate is legitimately *accepted*
/// now (no longer a rejection case) -- see `InternalsClientIdentityDescriptorTests` for that half,
/// since proving it doesn't throw here would mean letting `result()` run all the way to
/// `schedule(...)`.
struct BackgroundDownloadTaskTests {

    @Test
    func result_whenClientCertificateIsBytesBacked_throwsUnsupportedConfigurationError() async throws {
        // Given -- valid, complete, in-memory bytes rather than a file path.
        let client = Certificates().client()
        let certificateBytes = try [UInt8](Data(contentsOf: client.certificateURL))
        let privateKeyBytes = try [UInt8](Data(contentsOf: client.privateKeyURL))

        let task = BackgroundDownloadTask(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        ) {
            BaseURL("localhost")

            SecureConnection {
                RequestDL.Certificates(certificateBytes)
                PrivateKey(privateKeyBytes)
            }
        }

        // When / Then
        do {
            try await task.result()
            Issue.record("Expected BackgroundDownloadUnsupportedConfigurationError")
        } catch let error as BackgroundDownloadUnsupportedConfigurationError {
            guard case .nonFileBackedSource = error.reason else {
                Issue.record("Expected .nonFileBackedSource, got \(error.reason)")
                return
            }
            #expect((error as any Error).localizedDescription == error.description)
            #expect(error.description.contains("file path"))
        }
    }

    @Test
    func result_whenPrivateKeyIsPasswordProtected_throwsUnsupportedConfigurationError() async throws {
        // Given
        let client = Certificates().client(password: true)

        let task = BackgroundDownloadTask(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        ) {
            BaseURL("localhost")

            SecureConnection {
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                PrivateKey(
                    client.privateKeyURL.absolutePath(percentEncoded: false),
                    password: NIOSSLSecureBytes("password".utf8)
                )
            }
        }

        // When / Then
        do {
            try await task.result()
            Issue.record("Expected BackgroundDownloadUnsupportedConfigurationError")
        } catch let error as BackgroundDownloadUnsupportedConfigurationError {
            guard case .passwordProtectedPrivateKey = error.reason else {
                Issue.record("Expected .passwordProtectedPrivateKey, got \(error.reason)")
                return
            }
        }
    }

    /// Only half a client identity configured (`Certificates` without `PrivateKey`) must still be
    /// rejected -- it's just as unable to answer a challenge as any other unsupported shape.
    @Test
    func result_whenContentConfiguresOnlyCertificateChain_throwsUnsupportedConfigurationError() async throws {
        // Given
        let client = Certificates().client()

        let task = BackgroundDownloadTask(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        ) {
            BaseURL("localhost")

            SecureConnection {
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
            }
        }

        // When / Then
        do {
            try await task.result()
            Issue.record("Expected BackgroundDownloadUnsupportedConfigurationError")
        } catch let error as BackgroundDownloadUnsupportedConfigurationError {
            guard case .incompleteClientIdentity = error.reason else {
                Issue.record("Expected .incompleteClientIdentity, got \(error.reason)")
                return
            }
        }
    }

    /// `Insecure.SHA1` isn't one of `Internals.SPKIHash.KnownAlgorithm`'s three cases, so it pins
    /// correctly live (see `InternalsServerTrustPolicyTests`) but can't be captured for a relaunch
    /// -- exactly the same "works live, not here" split `result_whenClientCertificateIsBytesBacked...`
    /// above exercises for mTLS.
    @Test
    func result_whenSPKIPinningUsesUnnamedAlgorithm_throwsUnsupportedConfigurationError() async throws {
        // Given -- any digest of the right byte count for the algorithm; SPKIHash's own length
        // validation, not a real match against a server certificate, is what this test needs.
        let dummyDigest = Data(repeating: 0, count: Insecure.SHA1.Digest.byteCount)

        let task = BackgroundDownloadTask(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        ) {
            BaseURL("localhost")

            SecureConnection {
                SPKIPinning {
                    SPKIHash(dummyDigest, algorithm: Insecure.SHA1.self)
                }
            }
        }

        // When / Then
        do {
            try await task.result()
            Issue.record("Expected BackgroundDownloadUnsupportedConfigurationError")
        } catch let error as BackgroundDownloadUnsupportedConfigurationError {
            guard case .spkiPinningAlgorithmNotSupported = error.reason else {
                Issue.record("Expected .spkiPinningAlgorithmNotSupported, got \(error.reason)")
                return
            }
            #expect((error as any Error).localizedDescription == error.description)
            #expect(error.description.contains("SHA-256"))
        }
    }
}

#endif
