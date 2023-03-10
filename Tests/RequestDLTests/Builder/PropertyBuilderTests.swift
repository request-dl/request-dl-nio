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
        let (_, request) = await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is Headers.ContentType)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testLimitedNotAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 99, macOS 99, watchOS 99, tvOS 99, *) {
                Headers.ContentType(.json)
            }
        }

        // When
        let (_, request) = await resolve(TestProperty(property))

        // Then
        print(type(of: property))
        XCTAssertTrue(property is _OptionalContent<Headers.ContentType>)
        XCTAssertNil(request.allHTTPHeaderFields)
    }

    func testLimitedAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 14, macOS 12, watchOS 7, tvOS 14, *) {
                Headers.ContentType(.json)
            }
        }

        // When
        let (_, request) = await resolve(TestProperty(property))

        // Then
        print(type(of: property))
        XCTAssertTrue(property is _OptionalContent<Headers.ContentType>)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}