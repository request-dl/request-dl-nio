/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersFlatMapTests: XCTestCase {

    struct FlatMapError: Error {}

    struct FailedTaskError: Error {}

    func testFlatMap() async throws {
        // Given
        let flatMapCalled = SendableBox(false)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
        }
        .flatMap { _ in
            flatMapCalled(true)
            return true
        }
        .result()

        // Then
        XCTAssertTrue(flatMapCalled())
        XCTAssertTrue(result)
    }

    func testFlatMapWithError() async throws {
        // Given
        let error = FlatMapError()

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
            }
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
        let result = try await MockedTask(content: {
            AsyncProperty {
                throw FailedTaskError()
            }
        })
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
            _ = try await MockedTask(content: {
                AsyncProperty {
                    throw FailedTaskError()
                }
            })
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
