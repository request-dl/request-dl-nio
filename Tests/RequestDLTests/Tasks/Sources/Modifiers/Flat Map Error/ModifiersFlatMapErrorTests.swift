/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersFlatMapErrorTests {

    struct FlatMapError: Error {}

    struct TransformedError: Error {}

    @Test
    func flatMap() async throws {
        // Given
        let flatMapCalled = SendableBox(false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .flatMapError { _ in
            flatMapCalled(true)
        }
        .result()

        // Then
        #expect(!flatMapCalled())
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
    func flatMapErrorThrowingMockError() async throws {
        // Given
        let error = FlatMapError()
        let transformedError = TransformedError()
        let mapError = SendableBox(false)

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
            }
            .flatMap { _ in throw error }
            .flatMapError(FlatMapError.self) { _ in
                mapError(true)
                throw transformedError
            }
            .result()
        } catch is TransformedError {} catch {
            throw error
        }

        // Then
        #expect(mapError())
    }
}
