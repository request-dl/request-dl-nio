/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class DataTaskTests: XCTestCase {

    func testDataTask() async throws {
        // Given
        let certificate = RequestDLInternals.Certificates().server()
        let output = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8090,
            response: output
        ).run { baseURL in
            let data = try await DataTask {
                BaseURL(baseURL)
                Path("index")

                SecureConnection {
                    Trusts(certificate.certificateURL.absolutePath(percentEncoded: false))
                }
            }
            .ignoresProgress()
            .extractPayload()
            .result()

            let result = try HTTPResult<String>.resolve(data)

            // Then
            XCTAssertEqual(result.response, output)
        }
    }
}
