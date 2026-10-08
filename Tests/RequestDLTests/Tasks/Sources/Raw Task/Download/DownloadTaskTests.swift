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
import struct Foundation.Data
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

    /// A response with no separator in it is one item, so a maximum smaller than it must end the
    /// read with the public error.
    @Test
    func download_whenAnItemOutgrowsTheMaximum_throwsReadingModeItemTooLargeError() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        defer { localServer.cleanup(at: uri) }

        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello World"), at: uri)

        let certificate = Certificates().server()

        // When
        let result = try await DownloadTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }

            ReadingMode(separator: "\n", maximumItemSize: 8)
        }
        .result()

        // Then
        await #expect(throws: ReadingModeItemTooLargeError(maximumItemSize: 8)) {
            for try await _ in result.payload {}
        }
    }

    #if canImport(NIOCore)

    /// The same read, pinned to `.nio`: the default executor on Darwin is `.urlSession`, so the
    /// test above only reaches the other body path there.
    @Test
    func download_whenAnItemOutgrowsTheMaximum_onNIO_throwsReadingModeItemTooLargeError() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        defer { localServer.cleanup(at: uri) }

        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello World"), at: uri)

        let certificate = Certificates().server()

        // When
        let result = try await DownloadTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }

            ReadingMode(separator: "\n", maximumItemSize: 8)
        }
        .result()

        // Then
        await #expect(throws: ReadingModeItemTooLargeError(maximumItemSize: 8)) {
            for try await _ in result.payload {}
        }
    }

    #endif

    @Test
    func download_whenTheMaximumIsLargeEnough_deliversTheWholeBody() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        defer { localServer.cleanup(at: uri) }

        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello World"), at: uri)

        let certificate = Certificates().server()

        // When
        let result = try await DownloadTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }

            ReadingMode(separator: "\n", maximumItemSize: 1_000_000)
        }
        .result()

        var body = Data()
        for try await part in result.payload {
            body.append(part)
        }

        // Then
        #expect(try HTTPResult<String>(body).response == "Hello World")
    }
}

#if canImport(Darwin)

extension DownloadTaskTests {

    /// Forced deterministically rather than relying on `resolveExecutor()`'s own default
    /// preference the way `dataTask()` above does: same round trip, pinned explicitly to
    /// `.urlSession`. Darwin-only: `.urlSession` isn't a real executor anywhere else, so pinning
    /// it there is not this test's intent.
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
