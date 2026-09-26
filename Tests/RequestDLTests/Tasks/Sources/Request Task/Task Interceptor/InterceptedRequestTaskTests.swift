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

    fileprivate struct FlagKey: RequestEnvironmentKey {
        static let defaultValue = false
    }

    fileprivate struct FlagReadingInterceptor<Element: Sendable>: RequestTaskInterceptor {

        @RequestEnvironment(\.interceptorFlag) var flag

        let callback: @Sendable (Bool) -> Void

        func output(_ result: Result<Element, Error>) {
            callback(flag)
        }
    }

    @Test
    func interceptor_readsEnvironmentSetOnTheSameChain() async throws {
        // Given: the environment is set on the same task chain as the interceptor itself --
        // `InterceptedRequestTask._result(environment:)` only threaded `environment` into the
        // wrapped task, never into the interceptor's own `@RequestEnvironment` properties.
        let observedFlag = InlineProperty(wrappedValue: false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .interceptor(
            FlagReadingInterceptor {
                observedFlag.wrappedValue = $0
            }
        )
        .environment(\.interceptorFlag, true)
        .result()

        // Then
        #expect(observedFlag.wrappedValue)
    }
}

extension RequestEnvironmentValues {

    fileprivate var interceptorFlag: Bool {
        get { self[InterceptedRequestTaskTests.FlagKey.self] }
        set { self[InterceptedRequestTaskTests.FlagKey.self] = newValue }
    }
}
