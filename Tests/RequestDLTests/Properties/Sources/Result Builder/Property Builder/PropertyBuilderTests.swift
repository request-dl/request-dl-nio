/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class PropertyBuilderTests: XCTestCase {

    func testSingleBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            Headers.ContentType(.json)
        }

        // When
        let (_, request) = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is Headers.ContentType)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "application/json")
    }

    #if !os(Linux)
    func testLimitedNotAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 99, macOS 99, watchOS 99, tvOS 99, *) {
                Headers.ContentType(.json)
            }
        }

        // When
        let (_, request) = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is _OptionalContent<Headers.ContentType>)
        XCTAssertTrue(request.headers.isEmpty)
    }
    #endif

    func testLimitedAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 14, macOS 12, watchOS 7, tvOS 14, *) {
                Headers.ContentType(.json)
            }
        }

        // When
        let (_, request) = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is _OptionalContent<Headers.ContentType>)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "application/json")
    }
}
