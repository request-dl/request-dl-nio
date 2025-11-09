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
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        defer { localServer.cleanup(at: uri) }

        let certificate = Certificates().server()
        let output = "Hello World"
        let upload = Data.randomData(length: 1_024)

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.insert(response, at: uri)

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            SecureConnection {
                Trusts(certificate.certificateURL.absolutePath(percentEncoded: false))
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
