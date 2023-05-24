/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class DownloadTaskTests: XCTestCase {

    var localServer: LocalServer!

    override func setUp() async throws {
        try await super.setUp()
        localServer = try await .init(.standard)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        localServer = nil
    }

    func testDataTask() async throws {
        // Given
        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        await localServer.register(response)
        defer { localServer.releaseConfiguration() }

        // When
        let data = try await DownloadTask {
            BaseURL(localServer.baseURL)
            Path("index")

            SecureConnection {
                Trusts(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .ignoresDownloadProgress()
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        XCTAssertEqual(result.response, output)
    }
}
