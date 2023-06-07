/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class MockedTaskTests: XCTestCase {

    func testMock_whenHeadersAndData() async throws {
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
        .ignoresProgress()
        .result()

        // Then
        let response = result.head

        XCTAssertNotNil(response)
        XCTAssertEqual(response.status.code, statusCode)
        XCTAssertEqual(result.payload, data)

        XCTAssertEqual(response.url?.absoluteString, "https://localhost")
        XCTAssertEqual(response.headers, .init([
            ("Accept", "application/json"),
            ("Content-Type", "text/plain"),
            ("Content-Length", String(data.count))
        ]))
    }

    func testMock_whenDefaultValues() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            Payload(data: data)
        }
        .ignoresProgress()
        .result()

        // Then
        let head = result.head

        XCTAssertEqual(head.status.code, 200)
        XCTAssertEqual(result.payload, data)
        XCTAssertEqual(head.headers, .init([
            ("Content-Type", "application/octet-stream"),
            ("Content-Length", String(data.count))
        ]))
    }
}

@available(*, deprecated)
extension MockedTaskTests {

    func testMock() async throws {
        // Given
        let statusCode: UInt = 200
        let headers = [
            "Content-Type": "application/json",
            "Accept": "text/html"
        ]
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask(
            statusCode: StatusCode(statusCode),
            headers: headers,
            data: { data }
        )
        .result()

        // Then
        let response = result.head

        XCTAssertNotNil(response)
        XCTAssertEqual(response.status.code, statusCode)
        XCTAssertEqual(result.payload, data)

        XCTAssertEqual(response.headers.count, headers.count)
        XCTAssertTrue(headers.allSatisfy { key, value in
            response.headers.contains(name: key) {
                $0 == value
            }
        })
    }

    func testDefaultValues() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask { data }
            .result()

        // Then
        let head = result.head

        XCTAssertEqual(head.status.code, 200)
        XCTAssertEqual(result.payload, data)
        XCTAssertTrue(head.headers.isEmpty)
    }
}
