/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersCollectBytesTests: XCTestCase {

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

    func testCollect_whenUploadStep_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response)

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
        .collectBytes()
        .extractPayload()
        .result()

        let data = try await Data(Array(bytes).joined())

        // Then
        XCTAssertEqual(try HTTPResult(data).response, message)
    }
}
