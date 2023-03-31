/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ModifiersFlatMapTests: XCTestCase {

    struct FlatMapError: Error {}

    struct FailedTaskError: Error {}

    struct FailedTask: Task {

        func result() async throws -> Data {
            throw FailedTaskError()
        }
    }

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

    func testFailedTestWithSuccessMapping() async throws {
        // Given
        let success = Data("Hello World".utf8)

        // When
        let result = try await FailedTask()
            .flatMap { _ in
                success
            }
            .result()

        // Then
        XCTAssertEqual(result, success)
    }

    func testFailedTestWithFailureMapping() async throws {
        // Given
        let error = FlatMapError()
        var failed = false

        // When
        do {
            _ = try await FailedTask()
                .flatMap { _ in
                    throw error
                }
                .result()
        } catch is FlatMapError {
            failed = true
        } catch {
            throw error
        }

        // Then
        XCTAssertTrue(failed)
    }
}
