/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersOnStatusCodeTests: XCTestCase {

    struct AnyError: Error {}

    func testStatusCode() async throws {
        // Given
        let statusCode: StatusCode = .ok
        var throwAnyError = false

        // When
        do {
            _ = try await MockedTask(
                status: status(statusCode),
                content: {
                    BaseURL("localhost")
                }
            )
            .ignoresProgress()
            .onStatusCode(statusCode) { _ in
                throw AnyError()
            }
            .result()
        } catch is AnyError {
            throwAnyError = true
        } catch { throw error }

        // Then
        XCTAssertTrue(throwAnyError)
    }

    func testStatusCodeRange() async throws {
        // Given
        let statusCodes = StatusCode.ok ..< .badRequest
        var received = [StatusCode]()

        // When
        for statusCode in StatusCode.continue ... .networkAuthenticationRequired {
            do {
                _ = try await MockedTask(
                    status: status(statusCode),
                    content: {
                        BaseURL("localhost")
                    }
                )
                .ignoresProgress()
                .onStatusCode(statusCodes) { _ in
                    throw AnyError()
                }
                .result()
            } catch is AnyError {
                received.append(statusCode)
            } catch { throw error }
        }

        // Then
        XCTAssertEqual(statusCodes.count, received.count)
        XCTAssertTrue(received.allSatisfy {
            statusCodes.contains($0)
        })
    }

    func testSuccessStatusCodeSet() async throws {
        // Given
        let statusCodeSet: StatusCodeSet = .success
        var received = [StatusCode]()

        // When
        for statusCode in StatusCode.continue ... .networkAuthenticationRequired {
            do {
                _ = try await MockedTask(
                    status: status(statusCode),
                    content: {
                        BaseURL("localhost")
                    }
                )
                .ignoresProgress()
                .onStatusCode(statusCodeSet) { _ in
                    throw AnyError()
                }
                .result()
            } catch is AnyError {
                received.append(statusCode)
            } catch { throw error }
        }

        // Then
        XCTAssertEqual(statusCodeSet.count, received.count)
        XCTAssertTrue(received.allSatisfy {
            statusCodeSet.contains($0)
        })
    }

    func testSuccessAndRedirectStatusCodeSet() async throws {
        // Given
        let statusCodeSet: StatusCodeSet = .successAndRedirect
        var received = [StatusCode]()

        // When
        for statusCode in StatusCode.continue ... .networkAuthenticationRequired {
            do {
                _ = try await MockedTask(
                    status: status(statusCode),
                    content: {
                        BaseURL("localhost")
                    }
                )
                .ignoresProgress()
                .onStatusCode(statusCodeSet) { _ in
                    throw AnyError()
                }
                .result()
            } catch is AnyError {
                received.append(statusCode)
            } catch { throw error }
        }

        // Then
        XCTAssertEqual(statusCodeSet.count, received.count)
        XCTAssertTrue(received.allSatisfy {
            statusCodeSet.contains($0)
        })
    }
}

extension ModifiersOnStatusCodeTests {

    func status(_ statusCode: StatusCode) -> ResponseHead.Status {
        .init(code: statusCode.rawValue, reason: "Mocked")
    }
}
