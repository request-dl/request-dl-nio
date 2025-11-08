/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct DownloadTaskTests {

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
    func dataTask() async throws {
        // Given
        let localServer = try #require(localServer)

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
