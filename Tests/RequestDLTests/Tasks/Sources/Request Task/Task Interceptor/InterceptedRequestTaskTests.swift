//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

struct InterceptedRequestTaskTests {

    struct Intercepted<Element: Sendable>: RequestTaskInterceptor {

        let callback: @Sendable () -> Void

        func output(_ result: Result<Element, Error>) {
            callback()
        }
    }

    struct ResultCapturingInterceptor<Element: Sendable>: RequestTaskInterceptor {

        let callback: @Sendable (Result<Element, Error>) -> Void

        func output(_ result: Result<Element, Error>) {
            callback(result)
        }
    }

    struct SomeError: Error {}

    @Test
    func interceptor() async throws {
        // Given
        let expectation = AsyncSignal()
        let taskIntercepted = InlineProperty(wrappedValue: false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .interceptor(
            Intercepted {
                taskIntercepted.wrappedValue = true
                expectation.signal()
            }
        )
        .result()

        // Then
        try await expectation.wait()
        #expect(taskIntercepted.wrappedValue)
    }

    @Test
    func interceptorReceivesFailureAndRethrowsWhenTaskThrows() async throws {
        // Given
        let error = SomeError()
        let interceptedFailure = InlineProperty(wrappedValue: false)

        // When
        await #expect(throws: SomeError.self) {
            _ = try await MockedTask {
                BaseURL("localhost")
            }
            .flatMap { _ in throw error }
            .interceptor(
                ResultCapturingInterceptor {
                    if case .failure = $0 {
                        interceptedFailure.wrappedValue = true
                    }
                }
            )
            .result()
        }

        // Then
        #expect(interceptedFailure.wrappedValue)
    }
}
