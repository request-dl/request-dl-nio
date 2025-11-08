/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct UploadTaskTests {

    @Test
    func uploadTask() async throws {
        // Given
        let localServer = try await LocalServer(.standard)

        localServer.cleanup()
        defer { localServer.cleanup() }

        let certificate = Certificates().server()
        let output = "Hello World"
        let upload = Data.randomData(length: 1_024)

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.insert(response)

        // When
        let data = try await UploadTask {
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

            Payload(data: upload)
        }
        .collectData()
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.receivedBytes == upload.count)
        #expect(result.response == output)
    }
}
