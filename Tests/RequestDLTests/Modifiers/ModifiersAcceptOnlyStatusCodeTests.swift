/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ModifiersStatusCodeTests: XCTestCase {

    func testStatusCodeValid() async throws {
        // Given
        var statusCodeReceived = false

        // When
        _ = try await MockedTask(statusCode: .ok, data: Data.init)
            .onStatusCode(.ok) {
                statusCodeReceived = ($0.response as? HTTPURLResponse)?.statusCode == 200
            }
            .result()

        // Then
        XCTAssertTrue(statusCodeReceived)
    }

    func testStatusInvalid() async throws {
        // Given
        var statusCodeReceived = false

        // When
        _ = try await MockedTask(statusCode: .ok, data: Data.init)
            .onStatusCode(.accepted) {
                statusCodeReceived = ($0.response as? HTTPURLResponse)?.statusCode == 200
            }
            .result()

        // Then
        XCTAssertFalse(statusCodeReceived)
    }

    func testRangeOfStatusCode() async throws {
        // Given
        let statusCodes: Range<StatusCode> = .ok ..< .badGateway
        var received = [StatusCode]()

        // When
        for statusCode in statusCodes {
            _ = try await MockedTask(statusCode: statusCode, data: Data.init)
                .onStatusCode(statusCodes) { _ in
                    received.append(statusCode)
                }
                .result()
        }

        // Then
        XCTAssertEqual(statusCodes.count, received.count)
        XCTAssert(statusCodes.allSatisfy {
            received.contains($0)
        })
    }

    func testSuccessStatusCodeSet() async throws {
        // Given
        let statusCodeSet: StatusCodeSet = .success
        var received = [StatusCode]()

        // When
        for rawValue in 0 ..< 600 {
            let statusCode = StatusCode(rawValue)

            _ = try await MockedTask(statusCode: statusCode, data: Data.init)
                .onStatusCode(statusCodeSet) { _ in
                    received.append(statusCode)
                }
                .result()
        }

        // Then
        XCTAssertEqual(statusCodeSet.count, received.count)
        XCTAssert(received.allSatisfy {
            statusCodeSet.contains($0)
        })
    }

    func testSuccessAndRedirectStatusCodeSet() async throws {
        // Given
        let statusCodeSet: StatusCodeSet = .successAndRedirect
        var received = [StatusCode]()

        // When
        for rawValue in 0 ..< 600 {
            let statusCode = StatusCode(rawValue)

            _ = try await MockedTask(statusCode: statusCode, data: Data.init)
                .onStatusCode(statusCodeSet) { _ in
                    received.append(statusCode)
                }
                .result()
        }

        // Then
        XCTAssertEqual(statusCodeSet.count, received.count)
        XCTAssert(received.allSatisfy {
            statusCodeSet.contains($0)
        })
    }
}
