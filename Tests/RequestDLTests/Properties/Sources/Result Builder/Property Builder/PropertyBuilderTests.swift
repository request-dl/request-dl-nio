/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class PropertyBuilderTests: XCTestCase {

    func testSingleBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            CacheHeader()
                .public(true)
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is CacheHeader)
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
    }

    #if !os(Linux)
    func testLimitedNotAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 99, macOS 99, watchOS 99, tvOS 99, visionOS 99, *) {
                CacheHeader()
                    .public(true)
            }
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is _OptionalContent<CacheHeader>)
        XCTAssertTrue(resolved.request.headers.isEmpty)
    }
    #endif

    func testLimitedAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 14, macOS 12, watchOS 7, tvOS 14, *) {
                CacheHeader()
                    .public(true)
            }
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is _OptionalContent<CacheHeader>)
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
    }
}
