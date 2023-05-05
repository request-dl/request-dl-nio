/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class QueryTests: XCTestCase {

    var urlEncoder: URLEncoder!

    override func setUp() async throws {
        try await super.setUp()
        urlEncoder = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        urlEncoder = nil
    }

    // MARK: - Default

    func testQuery_whenSingleInteger() async throws {
        // Given
        let key = "foo"
        let value = 123

        // When
        let (_, request) = try await resolve(TestProperty {
            Query(value, forKey: key)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com?\(key)=\(value)")
    }

    func testQuery_whenSingleString() async throws {
        // Given
        let key = "foo"
        let value = "bar"

        // When
        let (_, request) = try await resolve(TestProperty {
            Query(value, forKey: key)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com?\(key)=\(value)")
    }

    // MARK: - Optional

    func testQuery_whenOptionalSomeStringWithLiteralStyle() async throws {
        // Given
        let key = "foo"
        let value = "bar"

        // When
        let (_, request) = try await resolve(TestProperty {
            Query<String?>(value, forKey: key)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com?\(key)=\(value)")
    }

    func testQuery_whenOptionalNoneStringWithLiteralStyle() async throws {
        // Given
        let key = "foo"

        // When
        let (_, request) = try await resolve(TestProperty {
            Query<String?>(nil, forKey: key)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com?\(key)=nil")
    }

    func testQuery_whenOptionalSomeStringWithEmptyStyle() async throws {
        // Given
        let key = "foo"
        let value = "bar"

        urlEncoder.optionalStyle = .empty

        // When
        let (_, request) = try await resolve(TestProperty {
            Query<String?>(value, forKey: key)
                .urlEncoder(urlEncoder)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com?\(key)=\(value)")
    }

    func testQuery_whenOptionalNoneStringWithEmptyStyle() async throws {
        // Given
        let key = "foo"

        urlEncoder.optionalStyle = .empty

        // When
        let (_, request) = try await resolve(TestProperty {
            Query<String?>(nil, forKey: key)
                .urlEncoder(urlEncoder)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com")
    }

    // MARK: - Flag

    func testQuery_whenSingleTrueFlagWithLiteral() async throws {
        // Given
        let key = "foo"
        let value = true

        // When
        let (_, request) = try await resolve(TestProperty {
            Query(value, forKey: key)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com?\(key)=\(value)")
    }

    func testQuery_whenSingleFalseFlagWithLiteral() async throws {
        // Given
        let key = "foo"
        let value = false

        // When
        let (_, request) = try await resolve(TestProperty {
            Query(value, forKey: key)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com?\(key)=\(value)")
    }

    func testQuery_whenSingleTrueFlagWithNumeric() async throws {
        // Given
        let key = "foo"
        let value = true

        urlEncoder.boolStyle = .numeric

        // When
        let (_, request) = try await resolve(TestProperty {
            Query(value, forKey: key)
                .urlEncoder(urlEncoder)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com?\(key)=1")
    }

    func testQuery_whenSingleFalseFlagWithNumeric() async throws {
        // Given
        let key = "foo"
        let value = false

        urlEncoder.boolStyle = .numeric

        // When
        let (_, request) = try await resolve(TestProperty {
            Query(value, forKey: key)
                .urlEncoder(urlEncoder)
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com?\(key)=0")
    }

    // MARK: - Date
    // MARK: - Array
    // MARK: - Dictionary
    // MARK: - Data
    

    func testNeverBody() async throws {
        // Given
        let property = Query(123, forKey: "key")

        // Then
        try await assertNever(property.body)
    }
}
