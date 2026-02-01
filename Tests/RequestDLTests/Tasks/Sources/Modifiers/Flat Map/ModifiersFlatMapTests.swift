/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersFlatMapTests {

    struct FlatMapError: Error {}

    struct FailedTaskError: Error {}

    @Test
    func flatMap() async throws {
        // Given
        let flatMapCalled = InlineProperty(wrappedValue: false)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
        }
        .flatMap { _ in
            flatMapCalled.wrappedValue = true
            return true
        }
        .result()

        // Then
        #expect(flatMapCalled.wrappedValue)
        #expect(result)
    }

    @Test
    func flatMapWithError() async throws {
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

    @Test
    func failedTestWithSuccessMapping() async throws {
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
        #expect(result == success)
    }

    @Test
    func failedTestWithFailureMapping() async throws {
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
        #expect(failed)
    }
}
