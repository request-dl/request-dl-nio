/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersCollectDataTests: XCTestCase {

    var localServer: LocalServer!

    override func setUp() async throws {
        try await super.setUp()
        localServer = try await .init(.standard)
        localServer.cleanup()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        localServer.cleanup()
        localServer = nil
    }

    func testCollect_whenIsResultOfAsyncBytes() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response)

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
        .collectBytes()
        .collectData()
        .extractPayload()
        .result()

        // Then
        XCTAssertEqual(try HTTPResult(data).response, message)
    }

    func testCollect_whenIsAsyncBytes() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response)

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
        .collectBytes()
        .extractPayload()
        .collectData()
        .result()

        // Then
        XCTAssertEqual(try HTTPResult(data).response, message)
    }

    func testCollect_whenIsAsyncResponse() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response)

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
        .collectData()
        .extractPayload()
        .result()

        // Then
        XCTAssertEqual(try HTTPResult(data).response, message)
    }
}
