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
        let expectation = AsyncSignal()
        let taskIntercepted = InlineProperty(wrappedValue: false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .interceptor(Intercepted {
            taskIntercepted.wrappedValue = true
            expectation.signal()
        })
        .result()

        // Then
        await expectation.wait()
        #expect(taskIntercepted.wrappedValue)
    }
}
