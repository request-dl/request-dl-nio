/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InterceptedRequestTaskTests {

    struct Intercepted<Element: Sendable>: RequestTaskInterceptor {

        let callback: @Sendable () -> Void

        func output(_ result: Result<Element, Error>) {
            callback()
        }
    }

    @Test
    func interceptor() async throws {
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
        await _fulfillment(of: [expectation], timeout: 3)
        #expect(taskIntercepted())
    }
}
