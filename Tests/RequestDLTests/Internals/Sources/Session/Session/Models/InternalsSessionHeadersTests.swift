/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class InternalsHeadersTests: XCTestCase {

    var headers: Internals.Headers!

    override func setUp() async throws {
        try await super.setUp()
        headers = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        headers = nil
    }

    func testHeaders_whenEmpty_shouldBeEmpty() async throws {
        XCTAssertTrue(headers.isEmpty)
    }

    func testHeaders_whenSetValue_shouldContainsValue() async throws {
        // Given
        let key = "Content-Type"
        let value = "application/json"

        // When
        headers.setValue(value, forKey: key)

        // Then
        XCTAssertEqual(headers.getValue(forKey: key), value)
    }

    func testHeaders_whenAddValue_shouldContainsTwoValues() async throws {
        // Given
        let key = "Content-Type"
        let value = "application/json"
        let addValue = "text/html"

        // When
        headers.setValue(value, forKey: key)
        headers.addValue(addValue, forKey: key)

        // Then
        XCTAssertEqual(headers.getValue(forKey: key), "\(value); \(addValue)")
    }

    func testHeaders_whenAddValue_shouldContainsValue() async throws {
        // Given
        let key = "Content-Type"
        let value = "application/json"
        let addValue = "text/html"

        // When
        headers.setValue(value, forKey: key)
        headers.addValue(addValue, forKey: key)

        // Then
        XCTAssertEqual(headers.getValue(forKey: key), "\(value); \(addValue)")
    }

    func testHeaders_whenSameKeysWithCaseDifference_shouldObtainSameValue() async throws {
        // Given
        let key1 = "Content-Type"
        let key2 = "Content-type"
        let value = "application/json"

        // When
        headers.setValue(value, forKey: key1)
        let value2 = headers.getValue(forKey: key2)

        // Then
        XCTAssertEqual(headers.getValue(forKey: key1), value2)
    }

    func testHeaders_whenMultipleKeys_shouldIterateOverThem() async throws {
        // Given
        let key1 = "Content-Type"
        let value1 = "application/json"

        let key2 = "Accept"
        let value2 = "text/html"

        let key3 = "Origin"
        let value3 = "https://google.com"

        // When
        headers.setValue(value1, forKey: key1)
        headers.setValue(value2, forKey: key2)
        headers.setValue(value3, forKey: key3)

        // Then
        XCTAssertEqual(headers.count, 3)

        XCTAssertTrue(Array(headers).allSatisfy {
            switch $0 {
            case key1:
                return $1 == value1
            case key2:
                return $1 == value2
            case key3:
                return $1 == value3
            default:
                return false
            }
        })
    }

    func testHeaders_whenBuildWithValues_shouldBeEqualAfterInstanciateWithHTTPHeaders() async throws {
        // Given
        let key1 = "Content-Type"
        let value1 = "application/json"

        let key2 = "Accept"
        let value2 = "text/html"

        let key3 = "Content-type"
        let value3 = "application/xml"

        // When
        headers.setValue(value1, forKey: key1)
        headers.setValue(value2, forKey: key2)
        headers.addValue(value3, forKey: key3)

        let httpHeaders = headers.build()
        let headers = Internals.Headers(httpHeaders)

        // Then
        XCTAssertEqual(headers.count, 2)

        XCTAssertTrue(Array(headers).allSatisfy {
            switch $0 {
            case key1:
                return $1 == "\(value1); \(value3)"
            case key2:
                return $1 == value2
            default:
                return false
            }
        })
    }

    func testHeaders_whenContainsValue() async throws {
        // Given
        let key = "Content-Type"
        let value = "application/x-www-form-urlencoded; charset=utf-8"

        // When
        headers.setValue(value, forKey: key)

        // Then
        XCTAssertTrue(headers.contains("charset=utf-8", forKey: key))
    }

    func testHeaders_whenInitWithTuples() async throws {
        // Given
        let rawHeaders = [
            ("Content-Type", "application/x-www-form-urlencoded"),
            ("content-type", "charset=utf-8")
        ]

        // When
        let headers = Internals.Headers(rawHeaders)

        // Then
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(
            headers.getValue(forKey: "Content-Type"),
            "application/x-www-form-urlencoded; charset=utf-8"
        )
    }

    func testHeaders_whenHashable() async throws {
        // Given
        let headers1 = Internals.Headers([
            ("Content-Type", "application/json")
        ])

        let headers2 = Internals.Headers([
            ("Accept", "text/html")
        ])

        // Given
        let sut = Set([headers1, headers1, headers2])

        // Then
        XCTAssertEqual(sut, [headers1, headers2])
    }
}
