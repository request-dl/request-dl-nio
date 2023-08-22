/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersKeyPathTests: XCTestCase {

    func testKeyPath() async throws {
        // Given
        let jsonObject = ["key": true]

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            Payload(jsonObject)
        }
        .collectData()
        .keyPath(\.key)
        .result()

        // Then
        XCTAssertEqual(result.payload, Data("true".utf8))
    }

    func testWrongKeyPath() async throws {
        // Given
        let jsonObject = ["key": true]
        var keyPathNotFound = false

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
                Payload(jsonObject)
            }
            .collectData()
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
        let jsonObject = ["key": true]

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            Payload(jsonObject)
        }
        .collectData()
        .extractPayload()
        .keyPath(\.key)
        .result()

        // Then
        XCTAssertEqual(result, Data("true".utf8))
    }

    func testWrongKeyPathInData() async throws {
        // Given
        let jsonObject = ["key": true]
        var keyPathNotFound = false

        // When
        do {
            _ = try await MockedTask {
                BaseURL("localhost")
                Payload(jsonObject)
            }
            .collectData()
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
