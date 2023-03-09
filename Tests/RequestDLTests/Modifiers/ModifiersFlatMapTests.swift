/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ModifiersFlatMapTests: XCTestCase {

    struct FlatMapError: Error {}

    func testFlatMap() async throws {
        // Given
        var flatMapCalled = false

        // When
        let result = try await MockedTask(data: Data.init)
            .flatMap { _ in
                flatMapCalled = true
                return true
            }
            .result()

        // Then
        XCTAssertTrue(flatMapCalled)
        XCTAssertTrue(result)
    }

    func testFlatMapWithError() async throws {
        // Given
        let error = FlatMapError()

        // When
        do {
            _ = try await MockedTask(data: Data.init)
                .flatMap { _ in
                    throw error
                }
                .result()
        } catch is FlatMapError {} catch {
            throw error
        }
    }
}
