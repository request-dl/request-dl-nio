//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

struct ModifiersFlatMapErrorTests {

    struct FlatMapError: Error {}

    struct TransformedError: Error {}

    @Test
    func flatMap() async throws {
        // Given
        let flatMapCalled = InlineProperty(wrappedValue: false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .flatMapError { _ in
            flatMapCalled.wrappedValue = true
        }
        .result()

        // Then
        #expect(!flatMapCalled.wrappedValue)
    }

    @Test
    func flatMapWithError() async throws {
        // Given
        let error = FlatMapError()

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .flatMapError { _ in
            throw error
        }
        .result()
    }

    @Test
    func flatMapErrorRethrowsOriginalErrorWhenTransformSucceeds() async throws {
        // Given
        let error = FlatMapError()
        let mapError = InlineProperty(wrappedValue: false)

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
            }
            .flatMap { _ in throw error }
            .flatMapError { _ in
                mapError.wrappedValue = true
            }
            .result()

            Issue.record("Expected the original error to be rethrown")
        } catch is FlatMapError {
        } catch {
            throw error
        }

        // Then
        #expect(mapError.wrappedValue)
    }

    @Test
    func flatMapErrorTypedRethrowsOriginalErrorWhenTransformSucceeds() async throws {
        // Given
        let error = FlatMapError()
        let mapError = InlineProperty(wrappedValue: false)

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
            }
            .flatMap { _ in throw error }
            .flatMapError(FlatMapError.self) { _ in
                mapError.wrappedValue = true
            }
            .result()

            Issue.record("Expected the original error to be rethrown")
        } catch is FlatMapError {
        } catch {
            throw error
        }

        // Then
        #expect(mapError.wrappedValue)
    }

    @Test
    func flatMapErrorThrowingMockError() async throws {
        // Given
        let error = FlatMapError()
        let transformedError = TransformedError()
        let mapError = InlineProperty(wrappedValue: false)

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
            }
            .flatMap { _ in throw error }
            .flatMapError(FlatMapError.self) { _ in
                mapError.wrappedValue = true
                throw transformedError
            }
            .result()
        } catch is TransformedError {} catch {
            throw error
        }

        // Then
        #expect(mapError.wrappedValue)
    }
}
