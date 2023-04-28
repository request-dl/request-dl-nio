/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class DownloadTaskTests: XCTestCase {

    func testDataTask() async throws {
        // Given
        let certificate = Certificates().server()
        let output = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8888,
            response: output
        ).run { baseURL in
            let data = try await DownloadTask {
                BaseURL(baseURL)
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
}
