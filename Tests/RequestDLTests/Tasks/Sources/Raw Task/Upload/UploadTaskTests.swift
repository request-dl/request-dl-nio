/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class UploadTaskTests: XCTestCase {

    func testUploadTask() async throws {
        // Given
        let certificate = Certificates().server()
        let output = "Hello World"
        let upload = Data.randomData(length: 1_024)

        // When
        try await InternalServer(
            host: "localhost",
            port: 8091,
            response: output
        ).run { baseURL in
            let data = try await UploadTask {
                BaseURL(baseURL)
                Path("index")

                SecureConnection {
                    Trusts(certificate.certificateURL.absolutePath(percentEncoded: false))
                }

                Payload(upload)
            }
            .ignoresProgress()
            .extractPayload()
            .result()

            let result = try HTTPResult<String>(data)

            // Then
            XCTAssertEqual(result.receivedBytes, upload.count)
            XCTAssertEqual(result.response, output)
        }
    }
}
