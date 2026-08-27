//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// Only covers `result()`'s validation guard -- the part that runs and throws before ever
/// touching `BackgroundDownloads.Session.shared`. Actually scheduling a download would start a
/// real `URLSessionConfiguration.background` session from this bare SwiftPM test harness, an
/// unsigned CLI process with none of the entitlements a real app target has; that path is not
/// exercised here, the same way this suite's mTLS tests don't exercise a real Keychain round trip
/// either.
struct BackgroundDownloadTaskTests {

    @Test
    func result_whenContentConfiguresSecureConnection_throwsUnsupportedConfigurationError() async throws {
        // Given
        let task = BackgroundDownloadTask(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        ) {
            BaseURL("localhost")

            SecureConnection {
                TrustRoots("/dev/null")
            }
        }

        // When / Then
        await #expect(throws: BackgroundDownloadUnsupportedConfigurationError.self) {
            try await task.result()
        }
    }

    @Test
    func result_whenContentConfiguresSecureConnection_errorReadsActionably() async throws {
        // Given
        let task = BackgroundDownloadTask(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        ) {
            BaseURL("localhost")

            SecureConnection {
                TrustRoots("/dev/null")
            }
        }

        // When / Then
        do {
            try await task.result()
            Issue.record("Expected BackgroundDownloadUnsupportedConfigurationError")
        } catch let error as BackgroundDownloadUnsupportedConfigurationError {
            #expect((error as any Error).localizedDescription == error.description)
            #expect(error.description.contains("SecureConnection"))
        }
    }
}

#endif
