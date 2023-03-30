/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import RequestDLInternals
@testable import RequestDL

class ModifiersIgnoresProgressTests: XCTestCase {

    func testIgnores_whenUploadStep_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates().server()
        let message = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8083,
            response: message
        ).run { baseURL in
            let bytes = try await DataTask {
                BaseURL(baseURL)
                Path("index")
                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath())
                    }
                }
            }
            .ignoresUploadProgress()
            .extractPayload()
            .result()

            let data = try await Data(Array(bytes).joined())

            // Then
            XCTAssertEqual(try HTTPResult.resolve(data).response, message)
        }
    }

    func testIgnores_whenDownloadStep_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates().server()
        let message = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8084,
            response: message
        ).run { baseURL in
            let data = try await DataTask {
                BaseURL(baseURL)
                Path("index")
                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath())
                    }
                }
            }
            .ignoresUploadProgress()
            .ignoresDownloadProgress()
            .extractPayload()
            .result()

            // Then
            XCTAssertEqual(try HTTPResult.resolve(data).response, message)
        }
    }

    func testIgnores_whenSkipProgress_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates().server()
        let message = "Hello World"

        // When
        try await InternalServer(
            host: "localhost",
            port: 8085,
            response: message
        ).run { baseURL in
            let data = try await DataTask {
                BaseURL(baseURL)
                Path("index")
                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath())
                    }
                }
            }
            .ignoresProgress()
            .extractPayload()
            .result()

            // Then
            XCTAssertEqual(try HTTPResult.resolve(data).response, message)
        }
    }
}
