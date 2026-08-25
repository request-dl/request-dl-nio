//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

struct DownloadTaskTests {

    @Test
    func dataTask() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        defer { localServer.cleanup(at: uri) }

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.insert(response, at: uri)

        // When
        let data = try await DownloadTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .collectData()
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }
}

#if canImport(Darwin)

extension DownloadTaskTests {

    /// Phase 9 of `URLSESSION_TASK.md`'s test-parity strategy, forced deterministically rather
    /// than relying on `resolveExecutor()`'s own default preference the way `dataTask()` above
    /// does -- same round trip, pinned explicitly to `.urlSession`. Darwin-only: `.urlSession`
    /// isn't a real executor anywhere else, so pinning it there is not this test's intent.
    @Test
    func dataTask_whenURLSessionRequired_deliversWholeBodyIntact() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        defer { localServer.cleanup(at: uri) }

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.insert(response, at: uri)

        // When
        let data = try await DownloadTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
                .requiredExecutor(.urlSession)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .collectData()
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }
}

#endif
