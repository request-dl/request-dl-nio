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
            Headers.Cache()
                .public(true)
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is Headers.Cache)
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
    }

    func testLimitedNotAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 99, macOS 99, watchOS 99, tvOS 99, *) {
                Headers.Cache()
                    .public(true)
            }
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is _OptionalContent<Headers.Cache>)
        XCTAssertTrue(resolved.request.headers.isEmpty)
    }

    func testLimitedAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 14, macOS 12, watchOS 7, tvOS 14, *) {
                Headers.Cache()
                    .public(true)
            }
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is _OptionalContent<Headers.Cache>)
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
    }
}
