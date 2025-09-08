/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class UploadTaskTests: XCTestCase {

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

    func testUploadTask() async throws {
        // Given
        let localServer = try XCTUnwrap(localServer)
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
                Trusts(certificate.certificateURL.absolutePath(percentEncoded: false))
            }

            Payload(data: upload)
        }
        .collectData()
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        XCTAssertEqual(result.receivedBytes, upload.count)
        XCTAssertEqual(result.response, output)
    }
}
