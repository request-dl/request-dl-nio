/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class HTTPHeadersTests: XCTestCase {

    var headers: HTTPHeaders!

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
        headers.set(name: key, value: value)

        // Then
        XCTAssertEqual(headers[key], [value])
    }

    func testHeaders_whenAddValue_shouldContainsTwoValues() async throws {
        // Given
        let key = "Content-Type"
        let value = "application/json; text/html"

        // When
        headers.set(name: key, value: value)

        // Then
        XCTAssertEqual(headers[key], [value])
    }

    func testHeaders_whenSameKeysWithCaseDifference_shouldObtainSameValue() async throws {
        // Given
        let key1 = "Content-Type"
        let key2 = "Content-type"
        let value = "application/json"

        // When
        headers.set(name: key1, value: value)
        let value2 = headers[key2]

        // Then
        XCTAssertEqual(headers[key1], value2)
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
        headers.set(name: key1, value: value1)
        headers.set(name: key2, value: value2)
        headers.set(name: key3, value: value3)

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

    func testHeaders_whenInitWithTuples() async throws {
        // Given
        let rawHeaders = [
            ("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")
        ]

        // When
        let headers = HTTPHeaders(rawHeaders)

        // Then
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(
            headers["Content-Type"],
            ["application/x-www-form-urlencoded; charset=utf-8"]
        )
    }

    func testHeaders_whenHashable() async throws {
        // Given
        let headers1 = HTTPHeaders([
            ("Content-Type", "application/json")
        ])

        let headers2 = HTTPHeaders([
            ("Accept", "text/html")
        ])

        // Given
        let sut = Set([headers1, headers1, headers2])

        // Then
        XCTAssertEqual(sut, [headers1, headers2])
    }
}

/*
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
         headers.set(name: key, value: value)

         // Then
         XCTAssertEqual(headers[key], [value])
     }

     func testHeaders_whenAddValue_shouldContainsTwoValues() async throws {
         // Given
         let key = "Content-Type"
         let value = "application/json"
         let addValue = "text/html"

         // When
         headers.set(name: key, value: value)
         headers.add(name: key, value: addValue)

         // Then
         XCTAssertEqual(headers[key], ["\(value)", "\(addValue)"])
     }

     func testHeaders_whenAddValue_shouldContainsValue() async throws {
         // Given
         let key = "Content-Type"
         let value = "application/json"
         let addValue = "text/html"

         // When
         headers.set(name: key, value: value)
         headers.add(name: key, value: addValue)

         // Then
         XCTAssertEqual(headers[key], [value, addValue])
     }

     func testHeaders_whenSameKeysWithCaseDifference_shouldObtainSameValue() async throws {
         // Given
         let key1 = "Content-Type"
         let key2 = "Content-type"
         let value = "application/json"

         // When
         headers.set(name: key1, value: value)
         let value2 = headers[key2]

         // Then
         XCTAssertEqual(headers[key1], value2)
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
         headers.set(name: key1, value: value1)
         headers.set(name: key2, value: value2)
         headers.set(name: key3, value: value3)

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
         headers.set(name: key1, value: value1)
         headers.set(name: key2, value: value2)
         headers.add(name: key3, value: value3)

         let httpHeaders = headers.build()
         let headers = Internals.Headers(httpHeaders)

         // Then
         XCTAssertEqual(headers.count, 3)

         XCTAssertTrue(headers.contains(value1, for: key1))
         XCTAssertTrue(headers.contains(value2, for: key2))
         XCTAssertTrue(headers.contains(value3, for: key3))
     }

     func testHeaders_whenContainsStructureValue() async throws {
         // Given
         let key = "Content-Type"
         let value = "application/x-www-form-urlencoded; charset=utf-8"

         // When
         headers.set(name: key, value: value)

         // Then
         XCTAssertTrue(headers.contains(value, for: key))
     }

     func testHeaders_whenInitWithTuples() async throws {
         // Given
         let rawHeaders = [
             ("Content-type", "application/json"),
             ("Content-Type", "application/x-www-form-urlencoded; charset=utf-8"),
             ("Accept", "text/html")
         ]

         // When
         let headers = Internals.Headers(rawHeaders)

         // Then
         XCTAssertEqual(headers.count, 3)
         XCTAssertEqual(
             headers["Content-Type"],
             [rawHeaders[0].1, rawHeaders[1].1]
         )
         XCTAssertEqual(
             headers["Accept"],
             [rawHeaders[2].1]
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

 */
