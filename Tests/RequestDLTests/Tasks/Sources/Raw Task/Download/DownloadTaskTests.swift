/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct DownloadTaskTests {

    @Test
    func dataTask() async throws {
        // Given
        let localServer = try await LocalServer(.standard)

        localServer.cleanup()
        defer { localServer.cleanup() }

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.insert(response)

        // When
        let data = try await DownloadTask {
            BaseURL(localServer.baseURL)
            Path("index")

            SecureConnection {
                #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                DefaultTrusts()
                AdditionalTrusts(certificate.certificateURL.absolutePath(percentEncoded: false))
                #else
                Trusts(certificate.certificateURL.absolutePath(percentEncoded: false))
                #endif
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
