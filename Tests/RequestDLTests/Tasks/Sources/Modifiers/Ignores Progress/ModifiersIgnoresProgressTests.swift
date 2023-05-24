/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersIgnoresProgressTests: XCTestCase {

    var localServer: LocalServer!

    override func setUp() async throws {
        try await super.setUp()
        localServer = try await .init(.standard)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        localServer = nil
    }

    func testIgnores_whenUploadStep_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        await localServer.register(response)
        defer { localServer.releaseConfiguration() }

        // When
        let bytes = try await UploadTask {
            BaseURL(localServer.baseURL)
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

    func testIgnores_whenDownloadStep_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        await localServer.register(response)
        defer { localServer.releaseConfiguration() }

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
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

    func testIgnores_whenSkipProgress_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        await localServer.register(response)
        defer { localServer.releaseConfiguration() }

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
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
