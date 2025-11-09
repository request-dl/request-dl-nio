/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersKeyPathTests {

    @Test
    func keyPath() async throws {
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
        #expect(result.payload == Data("true".utf8))
    }

    @Test
    func wrongKeyPath() async throws {
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
        #expect(keyPathNotFound)
    }

    @Test
    func keyPathInData() async throws {
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
        #expect(result == Data("true".utf8))
    }

    @Test
    func wrongKeyPathInData() async throws {
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
        #expect(keyPathNotFound)
    }
}
