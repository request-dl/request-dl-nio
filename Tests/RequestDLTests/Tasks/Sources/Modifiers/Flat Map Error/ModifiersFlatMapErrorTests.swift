/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersFlatMapErrorTests: XCTestCase {

    struct FlatMapError: Error {}

    struct TransformedError: Error {}

    func testFlatMap() async throws {
        // Given
        let flatMapCalled = SendableBox(false)

        // When
        _ = try await MockedTask(data: Data.init)
            .flatMapError { _ in
                flatMapCalled(true)
            }
            .result()

        // Then
        XCTAssertFalse(flatMapCalled())
    }

    func testFlatMapWithError() async throws {
        // Given
        let error = FlatMapError()

        // When
        _ = try await MockedTask(data: Data.init)
            .flatMapError { _ in
                throw error
            }
            .result()
    }

    func testFlatMapErrorThrowingMockError() async throws {
        // Given
        let error = FlatMapError()
        let transformedError = TransformedError()
        let mapError = SendableBox(false)

        // When
        do {
            _ = try await MockedTask(data: Data.init)
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
        XCTAssertTrue(mapError())
    }
}
