/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersIgnoresProgressTests: XCTestCase {

    func testIgnores_whenUploadStep_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8888,
            response: message
        ).run { baseURL in
            let bytes = try await UploadTask {
                BaseURL(baseURL)
                Path("index")
                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                    }
                }
            }
            .ignoresUploadProgress()
            .extractPayload()
            .result()

            let data = try await Data(Array(bytes).joined())

            // Then
            XCTAssertEqual(try HTTPResult(data).response, message)
        }
    }

    func testIgnores_whenDownloadStep_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8888,
            response: message
        ).run { baseURL in
            let data = try await UploadTask {
                BaseURL(baseURL)
                Path("index")
                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                    }
                }
            }
            .ignoresUploadProgress()
            .ignoresDownloadProgress()
            .extractPayload()
            .result()

            // Then
            XCTAssertEqual(try HTTPResult(data).response, message)
        }
    }

    func testIgnores_whenSkipProgress_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8888,
            response: message
        ).run { baseURL in
            let data = try await UploadTask {
                BaseURL(baseURL)
                Path("index")
                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                    }
                }
            }
            .ignoresProgress()
            .extractPayload()
            .result()

            // Then
            XCTAssertEqual(try HTTPResult(data).response, message)
        }
    }
}
