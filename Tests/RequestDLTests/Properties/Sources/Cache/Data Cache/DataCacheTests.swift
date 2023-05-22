/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class DataCacheTests: XCTestCase {

    let memoryCapacity: UInt64 = 8 * 1_024 * 1_024
    let diskCapacity: UInt64 = 64 * 1_024 * 1_024

    var dataCache: DataCache!

    override func setUp() async throws {
        try await super.setUp()
        dataCache = .init(
            memoryCapacity: 8 * 1_024 * 1_024,
            diskCapacity: 64 * 1_024 * 1_024
        )
    }

    override func tearDown() async throws {
        try await super.tearDown()
        dataCache = nil
    }

    func testCache_whenInit_shouldCapacityBeKnown() {
        // Then
        XCTAssertEqual(dataCache.memoryCapacity, memoryCapacity)
        XCTAssertEqual(dataCache.diskCapacity, diskCapacity)
    }

    func testCache_whenInitWithLowerCapacityPreviousSpecified_shouldBeMax() {
        // Given
        let memoryCapacity: UInt64 = 4 * 1_024 * 1_024
        let diskCapacity: UInt64 = 16 * 1_024 * 1_024

        // When
        let dataCache = DataCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity
        )

        // Then
        XCTAssertEqual(dataCache.memoryCapacity, self.memoryCapacity)
        XCTAssertEqual(dataCache.diskCapacity, self.diskCapacity)
    }

    func testCache_whenSetCapacityDirectly_shouldBeValid() {
        // Given
        let memoryCapacity: UInt64 = 4 * 1_024 * 1_024
        let diskCapacity: UInt64 = 16 * 1_024 * 1_024

        // When
        dataCache.memoryCapacity = memoryCapacity
        dataCache.diskCapacity = diskCapacity

        // Then
        XCTAssertEqual(dataCache.memoryCapacity, memoryCapacity)
        XCTAssertEqual(dataCache.diskCapacity, diskCapacity)
    }
}
