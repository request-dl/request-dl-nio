/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import RequestDLInternals
@testable import RequestDL

@available(*, deprecated)
final class ModifiersConvertBytesToDataTests: XCTestCase {

    func testBytesToData() async throws {
        // Given
        let resource = RequestDLInternals.Certificates().server()
        let message = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8080,
            response: message
        ).run {
            let data = try await DataTask {
                BaseURL("localhost:8080")
                Path("index")
                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath())
                    }
                }
            }
            .ignoresUploadProgress()
            .extractPayload()
            .convertBytesToData()
            .result()

            // Then
            XCTAssertEqual(try HTTPResult.resolve(data).response, message)
        }
    }

    func testBytesToDataBeforeExtractPayload() async throws {
        // Given
        let resource = RequestDLInternals.Certificates().server()
        let message = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8080,
            response: message
        ).run {
            let data = try await DataTask {
                BaseURL("localhost:8080")
                Path("index")
                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath())
                    }
                }
            }
            .ignoresUploadProgress()
            .convertBytesToData()
            .extractPayload()
            .result()

            // Then
            XCTAssertEqual(try HTTPResult.resolve(data).response, message)
        }
    }
}
