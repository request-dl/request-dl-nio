/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class InterceptedTaskTests: XCTestCase {

    struct Intercepted<Element>: TaskInterceptor {

        let callback: () -> Void

        func received(_ result: Result<Element, Error>) {
            callback()
        }
    }

    func testInterceptor() async throws {
        // Given
        let expectation = expectation(description: "Interceptor callback")
        var taskIntercepted = false

        // When
        _ = try await MockedTask(data: Data.init)
            .intercept(Intercepted {
                taskIntercepted = true
                expectation.fulfill()
            })
            .result()

        // Then
        await fulfillment(of: [expectation], timeout: 3)
        XCTAssertTrue(taskIntercepted)
    }
}
