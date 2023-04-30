/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class ModifiersStatusCodeTests: XCTestCase {

    func testSuccessStatusCodeSet() async throws {
        // Given
        let statusCodes = StatusCode(0) ..< 600
        let statusCodeSet: StatusCodeSet = .success
        var received = [StatusCode]()
        var failures = [StatusCode]()

        // When
        for statusCode in statusCodes {
            do {
                _ = try await MockedTask(statusCode: statusCode, data: Data.init)
                    .acceptOnlyStatusCode(statusCodeSet)
                    .result()
                received.append(statusCode)
            } catch is InvalidStatusCodeError<TaskResult<Data>> {
                failures.append(statusCode)
            } catch {
                throw error
            }
        }

        // Then
        XCTAssertEqual(statusCodeSet.count, received.count)
        XCTAssert(received.allSatisfy {
            statusCodeSet.contains($0)
        })

        XCTAssertTrue(failures.allSatisfy {
            !statusCodeSet.contains($0) && statusCodes.contains($0)
        })

        XCTAssertEqual(failures.count, statusCodes.count - statusCodeSet.count)
    }

    func testSuccessAndRedirectStatusCodeSet() async throws {
        // Given
        let statusCodes = StatusCode(0) ..< 600
        let statusCodeSet: StatusCodeSet = .successAndRedirect
        var received = [StatusCode]()
        var failures = [StatusCode]()

        // When
        for statusCode in statusCodes {
            do {
                _ = try await MockedTask(statusCode: statusCode, data: Data.init)
                    .acceptOnlyStatusCode(statusCodeSet)
                    .result()
                received.append(statusCode)
            } catch is InvalidStatusCodeError<TaskResult<Data>> {
                failures.append(statusCode)
            } catch {
                throw error
            }
        }

        // Then
        XCTAssertEqual(statusCodeSet.count, received.count)
        XCTAssert(received.allSatisfy {
            statusCodeSet.contains($0)
        })

        XCTAssertTrue(failures.allSatisfy {
            !statusCodeSet.contains($0) && statusCodes.contains($0)
        })

        XCTAssertEqual(failures.count, statusCodes.count - statusCodeSet.count)
    }
}
