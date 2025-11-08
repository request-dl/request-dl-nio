/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct UploadTaskTests {

    var localServer: LocalServer?

    override func setUp() async throws {
        try await super.setUp()
        localServer = try await .init(.standard)
        localServer?.cleanup()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        localServer?.cleanup()
        localServer = nil
    }

    @Test
    func uploadTask() async throws {
        // Given
        let localServer = try #require(localServer)
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
