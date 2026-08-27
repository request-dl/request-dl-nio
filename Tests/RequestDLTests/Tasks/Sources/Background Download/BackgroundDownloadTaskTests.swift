//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// Only covers `result()`'s validation guard -- the part that runs and throws (or doesn't) before
/// ever reaching `BackgroundDownloads.Session.shared.schedule(...)`. Actually scheduling a
/// download would start a real `URLSessionConfiguration.background` session from this bare
/// SwiftPM test harness, an unsigned CLI process with none of the entitlements a real app target
/// has; that path is not exercised here, the same way this suite's mTLS tests don't exercise a
/// real Keychain round trip either. `TrustRoots`/`AdditionalTrustRoots` resolving correctly is
/// covered directly against `Internals.ServerTrustPolicy` in `RequestDLInternalsTests`, including
/// a real handshake -- nothing here needs `Session` involved to prove that part works.
struct BackgroundDownloadTaskTests {

    @Test
    func result_whenContentConfiguresClientCertificate_throwsUnsupportedConfigurationError() async throws {
        // Given -- a real client certificate/key pair (mTLS), still rejected regardless of trust
        // roots being supported now.
        let client = Certificates().client()

        let task = BackgroundDownloadTask(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        ) {
            BaseURL("localhost")

            SecureConnection {
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
            }
        }

        // When / Then
        await #expect(throws: BackgroundDownloadUnsupportedConfigurationError.self) {
            try await task.result()
        }
    }

    @Test
    func result_whenContentConfiguresClientCertificate_errorReadsActionably() async throws {
        // Given
        let client = Certificates().client()

        let task = BackgroundDownloadTask(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        ) {
            BaseURL("localhost")

            SecureConnection {
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
            }
        }

        // When / Then
        do {
            try await task.result()
            Issue.record("Expected BackgroundDownloadUnsupportedConfigurationError")
        } catch let error as BackgroundDownloadUnsupportedConfigurationError {
            #expect((error as any Error).localizedDescription == error.description)
            #expect(error.description.contains("mTLS") || error.description.contains("client identity"))
        }
    }

    /// Only half a client identity configured (`Certificates` without `PrivateKey`) must still be
    /// rejected the same way a complete pair is -- it's just as unable to survive a relaunch, and
    /// `Internals.URLSessionIdentityPolicy` would reject it anyway once actually scheduled, just
    /// later and less clearly than doing it here.
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
        await #expect(throws: BackgroundDownloadUnsupportedConfigurationError.self) {
            try await task.result()
        }
    }
}

#endif
