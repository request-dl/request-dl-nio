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
        let (_, request) = try await resolve(TestProperty(property))

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
        let (_, request) = try await resolve(TestProperty(property))

        // Then
        print(type(of: property))
        XCTAssertTrue(property is _OptionalContent<Headers.ContentType>)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}

// swiftlint:disable identifier_name
@available(*, deprecated)
extension PropertyBuilderTests {

    func testTuple2() async throws {
        // Given
        let p0 = BaseURL("apple.com")
        let p1 = Headers.ContentType(.json)

        // When
        let tuple = PropertyBuilder.buildBlock(
            p0,
            p1
        )

        let (_, request) = try await resolve(tuple)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testTuple3() async throws {
        // Given
        let p0 = BaseURL("apple.com")
        let p1 = Headers.ContentType(.json)
        let p2 = Headers.Accept(.json)

        // When
        let tuple = PropertyBuilder.buildBlock(
            p0,
            p1,
            p2
        )

        let (_, request) = try await resolve(tuple)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testTuple4() async throws {
        // Given
        let p0 = BaseURL("apple.com")
        let p1 = Headers.ContentType(.json)
        let p2 = Headers.Accept(.json)
        let p3 = Headers.ContentLength(1_024)

        // When
        let tuple = PropertyBuilder.buildBlock(
            p0,
            p1,
            p2,
            p3
        )

        let (_, request) = try await resolve(tuple)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "1024")
    }

    func testTuple5() async throws {
        // Given
        let p0 = BaseURL("apple.com")
        let p1 = Headers.ContentType(.json)
        let p2 = Headers.Accept(.json)
        let p3 = Headers.ContentLength(1_024)
        let p4 = Authorization(.basic, token: "some")

        // When
        let tuple = PropertyBuilder.buildBlock(
            p0,
            p1,
            p2,
            p3,
            p4
        )

        let (_, request) = try await resolve(tuple)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "1024")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic some")
    }

    func testTuple6() async throws {
        // Given
        let p0 = BaseURL("apple.com")
        let p1 = Headers.ContentType(.json)
        let p2 = Headers.Accept(.json)
        let p3 = Headers.ContentLength(1_024)
        let p4 = Authorization(.basic, token: "some")
        let p5 = Path("api")

        // When
        let tuple = PropertyBuilder.buildBlock(
            p0,
            p1,
            p2,
            p3,
            p4,
            p5
        )

        let (_, request) = try await resolve(tuple)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://apple.com/api")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "1024")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic some")
    }

    func testTuple7() async throws {
        // Given
        let p0 = BaseURL("apple.com")
        let p1 = Headers.ContentType(.json)
        let p2 = Headers.Accept(.json)
        let p3 = Headers.ContentLength(1_024)
        let p4 = Authorization(.basic, token: "some")
        let p5 = Path("api")
        let p6 = Path("v1")

        // When
        let tuple = PropertyBuilder.buildBlock(
            p0,
            p1,
            p2,
            p3,
            p4,
            p5,
            p6
        )

        let (_, request) = try await resolve(tuple)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://apple.com/api/v1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "1024")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic some")
    }

    func testTuple8() async throws {
        // Given
        let p0 = BaseURL("apple.com")
        let p1 = Headers.ContentType(.json)
        let p2 = Headers.Accept(.json)
        let p3 = Headers.ContentLength(1_024)
        let p4 = Authorization(.basic, token: "some")
        let p5 = Path("api")
        let p6 = Path("v1")
        let p7 = Query("test", forKey: "q")

        // When
        let tuple = PropertyBuilder.buildBlock(
            p0,
            p1,
            p2,
            p3,
            p4,
            p5,
            p6,
            p7
        )

        let (_, request) = try await resolve(tuple)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://apple.com/api/v1?q=test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "1024")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic some")
    }
}
// swiftlint:enable identifier_name
