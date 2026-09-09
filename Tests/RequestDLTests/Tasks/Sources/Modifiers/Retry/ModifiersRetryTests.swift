//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

struct ModifiersRetryTests {

    struct TransientError: Error {}

    @Test
    func retryDoesNotRetryOnSuccess() async throws {
        // Given
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
        }
        .flatMap { _ -> Int in
            attempts.wrappedValue += 1
            return 42
        }
        .retry(.fixed(5, delay: .zero))
        .result()

        // Then
        #expect(result == 42)
        #expect(attempts.wrappedValue == 1)
    }

    @Test
    func retrySucceedsAfterTransientFailures() async throws {
        // Given
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
        }
        .flatMap { _ -> Int in
            attempts.wrappedValue += 1
            if attempts.wrappedValue < 3 {
                throw TransientError()
            }
            return attempts.wrappedValue
        }
        .retry(.fixed(5, delay: .zero))
        .result()

        // Then
        #expect(result == 3)
        #expect(attempts.wrappedValue == 3)
    }

    @Test
    func retryExhaustsAttemptsAndRethrowsLastError() async throws {
        // Given
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
            }
            .flatMap { _ -> Int in
                attempts.wrappedValue += 1
                throw TransientError()
            }
            .retry(.fixed(3, delay: .zero))
            .result()

            Issue.record("Expected the task to keep throwing")
        } catch is TransientError {
        } catch {
            throw error
        }

        // Then
        #expect(attempts.wrappedValue == 3)
    }

    @Test
    func retryStopsWhenShouldRetryReturnsFalse() async throws {
        // Given
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
            }
            .flatMap { _ -> Int in
                attempts.wrappedValue += 1
                throw TransientError()
            }
            .retry(.fixed(5, delay: .zero, shouldRetry: { _ in false }))
            .result()

            Issue.record("Expected the task to fail without retrying")
        } catch is TransientError {
        } catch {
            throw error
        }

        // Then
        #expect(attempts.wrappedValue == 1)
    }

    @Test
    func retryNeverRetriesCancellation() async throws {
        // Given
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
            }
            .flatMap { _ -> Int in
                attempts.wrappedValue += 1
                throw CancellationError()
            }
            .retry(.fixed(5, delay: .zero))
            .result()

            Issue.record("Expected cancellation to propagate without retrying")
        } catch is CancellationError {
        } catch {
            throw error
        }

        // Then
        #expect(attempts.wrappedValue == 1)
    }
}
