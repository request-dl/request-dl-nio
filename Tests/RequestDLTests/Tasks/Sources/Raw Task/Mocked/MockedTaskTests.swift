/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct MockedTaskTests {

    @Test
    func mock_whenHeadersAndData() async throws {
        // Given
        let statusCode: UInt = 200
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask(
            status: .init(code: statusCode, reason: "Ok"),
            content: {
                BaseURL("localhost")
                AcceptHeader(.json)
                Payload(data: data, contentType: .text)
            }
        )
        .collectData()
        .result()

        // Then
        let response = result.head

        #expect(response != nil)
        #expect(response.status.code == statusCode)
        #expect(result.payload == data)

        #expect(response.url?.absoluteString == "https://localhost")
        #expect(response.headers == .init([
            ("Accept", "application/json"),
            ("Content-Type", "text/plain"),
            ("Content-Length", String(data.count))
        ]))
    }

    @Test
    func mock_whenDefaultValues() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            Payload(data: data)
        }
        .collectData()
        .result()

        // Then
        let head = result.head

        #expect(head.status.code == 200)
        #expect(result.payload == data)
        #expect(head.headers == .init([
            ("Content-Type", "application/octet-stream"),
            ("Content-Length", String(data.count))
        ]))
    }
}
