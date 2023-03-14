/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ModifiersKeyPathTests: XCTestCase {

    func testKeyPath() async throws {
        // Given
        let data = Data("{ \"key\": true }".utf8)

        // When
        let result = try await MockedTask { data }
            .keyPath(\.key)
            .result()

        // Then
        XCTAssertEqual(result.data, Data("true".utf8))
    }

    func testWrongKeyPath() async throws {
        // Given
        let data = Data("{ \"key\": true }".utf8)
        var keyPathNotFound = false

        // When
        do {
            _ = try await MockedTask { data }
                .keyPath(\.items)
                .result()
        } catch is KeyPathNotFound {
            keyPathNotFound = true
        } catch { throw error }

        // Then
        XCTAssertTrue(keyPathNotFound)
    }

    func testKeyPathInData() async throws {
        // Given
        let data = Data("{ \"key\": true }".utf8)

        // When
        let result = try await MockedTask { data }
            .extractPayload()
            .keyPath(\.key)
            .result()

        // Then
        XCTAssertEqual(result, Data("true".utf8))
    }

    func testWrongKeyPathInData() async throws {
        // Given
        let data = Data("{ \"key\": true }".utf8)
        var keyPathNotFound = false

        // When
        do {
            _ = try await MockedTask { data }
                .extractPayload()
                .keyPath(\.items)
                .result()
        } catch is KeyPathNotFound {
            keyPathNotFound = true
        } catch { throw error }

        // Then
        XCTAssertTrue(keyPathNotFound)
    }

}
