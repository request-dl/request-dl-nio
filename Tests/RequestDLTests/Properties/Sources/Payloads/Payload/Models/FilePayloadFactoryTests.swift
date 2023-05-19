/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class FilePayloadFactoryTests: XCTestCase {

    func testFilePayload() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestDL.\(UUID())")
            .appendingPathComponent("file_payload")

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        try data.write(to: url)

        // When
        let payload = FilePayloadFactory(
            url: url,
            contentType: nil
        )

        // Then
        XCTAssertEqual(try payload().getData(), data)
    }
}
