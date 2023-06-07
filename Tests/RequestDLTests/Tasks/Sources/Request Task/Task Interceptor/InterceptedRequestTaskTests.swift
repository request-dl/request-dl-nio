/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InterceptedRequestTaskTests: XCTestCase {

    struct Intercepted<Element: Sendable>: RequestTaskInterceptor {

        let callback: @Sendable () -> Void

        func output(_ result: Result<Element, Error>) {
            callback()
        }
    }

    func testInterceptor() async throws {
        // Given
        let expectation = expectation(description: "Interceptor callback")
        let taskIntercepted = SendableBox(false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .interceptor(Intercepted {
            taskIntercepted(true)
            expectation.fulfill()
        })
        .result()

        // Then
        await fulfillment(of: [expectation], timeout: 3)
        XCTAssertTrue(taskIntercepted())
    }
}
