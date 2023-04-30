/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class InternalsStorageTests: XCTestCase {

    func testStorage_whenSetValue() async throws {
        // Given
        let key = "key"
        let value = 1
        let storage = Internals.Storage.shared

        // When
        storage.setValue(value, forKey: key)

        // Then
        XCTAssertEqual(storage.getValue(Int.self, forKey: key), value)
    }

    func testStorage_whenExpiredLifetime() async throws {
        // Given
        let lifetime = 2_500_000_000
        let key = "key"
        let value = 1

        // When
        let storage = Internals.Storage(lifetime: lifetime)
        storage.setValue(value, forKey: key)

        // Then
        XCTAssertNotNil(storage.getValue(Int.self, forKey: key))

        try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime * 2))

        XCTAssertNil(storage.getValue(Int.self, forKey: key))
    }
}
