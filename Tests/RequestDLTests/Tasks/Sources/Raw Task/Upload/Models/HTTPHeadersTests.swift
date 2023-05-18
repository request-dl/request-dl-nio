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

    func testHeaders_whenEmpty_shouldBeEmpty() {
        XCTAssertTrue(headers.isEmpty)
    }

    func testHeaders_whenInitWithSequence() {
        // Given
        let headers = HTTPHeaders([
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html"),
            ("Accept", "audio/mp3"),
            ("Authorization", "Bearer 123")
        ])

        // Then
        XCTAssertEqual(headers.count, 5)
        XCTAssertFalse(headers.isEmpty)

        XCTAssertEqual(headers.keys, [
            "Content-Type", "Accept", "Authorization"
        ])

        XCTAssertEqual(headers.first?.name, "Content-Type")
        XCTAssertEqual(headers.first?.value, "application/json")

        XCTAssertEqual(headers.last?.name, "Authorization")
        XCTAssertEqual(headers.last?.value, "Bearer 123")
    }

    func testHeaders_whenInitWithDictionaryLiteral() {
        // Given
        let headers: HTTPHeaders = [
            "Content-Type": "text/html",
            "Accept": "audio/mp3"
        ]

        // Then
        XCTAssertEqual(headers.first?.name, "Content-Type")
        XCTAssertEqual(headers.first?.value, "text/html")

        XCTAssertEqual(headers.last?.name, "Accept")
        XCTAssertEqual(headers.last?.value, "audio/mp3")
    }

    func testHeaders_whenSetValues() {
        // Given
        let values = [
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html"),
            ("Accept", "audio/mp3"),
            ("Authorization", "Bearer 123")
        ]

        // When
        for (name, value) in values {
            headers.set(name: name, value: value)
        }

        // Then
        let headersSequence = Array(headers).map { ($0.lowercased(), $1) }
        let expectingSequence = values[2..<values.count].map {
            ($0.lowercased(), $1)
        }

        XCTAssertEqual(headers.count, 3)

        XCTAssertEqual(headers.keys, [
            "Content-Type", "Accept", "Authorization"
        ])

        XCTAssertEqual(
            headersSequence.map(\.0),
            expectingSequence.map(\.0)
        )

        XCTAssertEqual(
            headersSequence.map(\.1),
            expectingSequence.map(\.1)
        )
    }

    func testHeaders_whenAddValues() {
        // Given
        let values = [
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html"),
            ("Accept", "audio/mp3"),
            ("Authorization", "Bearer 123")
        ]

        // When
        for (name, value) in values {
            headers.add(name: name, value: value)
        }

        // Then
        let headersSequence = Array(headers).map { ($0.lowercased(), $1) }
        let expectingSequence = values.map {
            ($0.lowercased(), $1)
        }

        XCTAssertEqual(headers.count, 5)

        XCTAssertEqual(headers.keys, [
            "Content-Type", "Accept", "Authorization"
        ])

        XCTAssertEqual(
            headersSequence.map(\.0),
            expectingSequence.map(\.0)
        )

        XCTAssertEqual(
            headersSequence.map(\.1),
            expectingSequence.map(\.1)
        )
    }

    func testHeaders_whenRemoveAddedValue() {
        // Given
        let values = [
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html"),
            ("Accept", "audio/mp3"),
            ("Authorization", "Bearer 123")
        ]

        // When
        for (name, value) in values {
            headers.add(name: name, value: value)
        }

        headers.remove(name: "CONTENT-TYPE")

        // Then
        XCTAssertEqual(headers.count, 2)

        XCTAssertEqual(headers.keys, [
            "Accept", "Authorization"
        ])

        XCTAssertEqual(headers.map(\.value), [
            "audio/mp3", "Bearer 123"
        ])
    }

    func testHeaders_whenFirstOfNames() {
        // Given
        let values = [
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html"),
            ("Accept", "audio/mp3"),
            ("Authorization", "Bearer 123")
        ]

        // When
        for (name, value) in values {
            headers.add(name: name, value: value)
        }

        let value1 = headers.first(name: "Content-TYPE")
        let value2 = headers.first(name: "ACCEPT")
        let value3 = headers.first(name: "authorization")

        // Then
        XCTAssertEqual(value1, "application/json")
        XCTAssertEqual(value2, "audio/mp3")
        XCTAssertEqual(value3, "Bearer 123")
    }

    func testHeaders_whenLastOfNames() {
        // Given
        let values = [
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html"),
            ("Accept", "audio/mp3"),
            ("Authorization", "Bearer 123")
        ]

        // When
        for (name, value) in values {
            headers.add(name: name, value: value)
        }

        let value1 = headers.last(name: "Content-TYPE")
        let value2 = headers.last(name: "ACCEPT")
        let value3 = headers.last(name: "authorization")

        // Then
        XCTAssertEqual(value1, "text/html")
        XCTAssertEqual(value2, "audio/mp3")
        XCTAssertEqual(value3, "Bearer 123")
    }

    func testHeaders_whenContainsName() {
        // Given
        let values = [
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html")
        ]

        // When
        for (name, value) in values {
            headers.add(name: name, value: value)
        }

        // Then
        let key = "content-type"

        XCTAssertTrue((0 ..< key.count).allSatisfy {
            let index = key.index(key.startIndex, offsetBy: $0)

            let uppercased = key[key.startIndex...index]
            let lowercased = key[key.index(after: index)..<key.endIndex]

            return headers.contains(name: "\(uppercased.uppercased())\(lowercased.lowercased())")
        })

        XCTAssertFalse(headers.contains(name: "Accept"))
    }

    func testHeaders_whenContainsNameWhere() {
        // Given
        let values = [
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html")
        ]

        // When
        for (name, value) in values {
            headers.add(name: name, value: value)
        }

        // Then
        XCTAssertTrue(headers.contains(name: "content-type") {
            $0 == "text/html"
        })

        XCTAssertFalse(headers.contains(name: "content-type") {
            $0 == "audio/mp3"
        })
    }

    func testHeaders_whenSubscriptByName() {
        // Given
        let values = [
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html")
        ]

        // When
        for (name, value) in values {
            headers.add(name: name, value: value)
        }

        // Then
        XCTAssertEqual(headers["CONTENT-TYPE"], values.map(\.1))

        XCTAssertNil(headers["Accept"])
    }

    func testHeaders_whenMergingWithRightExclusive() {
        // Given
        let sharedValues = [
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html"),
            ("Accept", "audio/mp3")
        ]

        let exclusiveValues = [
            ("Accept", "application/xml"),
            ("Authorization", "Bearer 123")
        ]

        let otherHeaders = HTTPHeaders(sharedValues + exclusiveValues)

        // When
        for (name, value) in sharedValues {
            headers.add(name: name, value: value)
        }

        headers = headers.merging(otherHeaders, by: +)

        // Then
        XCTAssertEqual(headers.count, 6)

        XCTAssertEqual(headers.keys, [
            "Content-Type", "Accept", "Authorization"
        ])

        XCTAssertEqual(headers.map(\.value), Array(Set(
            (sharedValues + exclusiveValues).map(\.1)
        )))
    }

    func testHeaders_whenSetValue_shouldContainsValue() {
        // Given
        let key = "Content-Type"
        let value = "application/json"

        // When
        headers.set(name: key, value: value)

        // Then
        XCTAssertEqual(headers[key], [value])
    }

    func testHeaders_whenAddValue_shouldContainsTwoValues() {
        // Given
        let key = "Content-Type"
        let value = "application/json; text/html"

        // When
        headers.set(name: key, value: value)

        // Then
        XCTAssertEqual(headers[key], [value])
    }

    func testHeaders_whenSameKeysWithCaseDifference_shouldObtainSameValue() {
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

    func testHeaders_whenMultipleKeys_shouldIterateOverThem() {
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

    func testHeaders_whenInitWithTuples() {
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

    func testHeaders_whenHashable() {
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

@available(*, deprecated)
extension HTTPHeadersTests {

    func testHeaders_whenInitWithDictionary() {
        // Given
        let headers = HTTPHeaders([
            "Content-Type": "text/html",
            "Accept": "audio/mp3"
        ])

        // Then
        XCTAssertEqual(headers.first?.name, "Content-Type")
        XCTAssertEqual(headers.first?.value, "text/html")

        XCTAssertEqual(headers.last?.name, "Accept")
        XCTAssertEqual(headers.last?.value, "audio/mp3")
    }
}

/*
 class InternalsHeadersTests: XCTestCase {

     var headers: Internals.Headers!

     override func setUp() {
         try await super.setUp()
         headers = .init()
     }

     override func tearDown() {
         try await super.tearDown()
         headers = nil
     }

     func testHeaders_whenEmpty_shouldBeEmpty() {
         XCTAssertTrue(headers.isEmpty)
     }

     func testHeaders_whenSetValue_shouldContainsValue() {
         // Given
         let key = "Content-Type"
         let value = "application/json"

         // When
         headers.set(name: key, value: value)

         // Then
         XCTAssertEqual(headers[key], [value])
     }

     func testHeaders_whenAddValue_shouldContainsTwoValues() {
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

     func testHeaders_whenAddValue_shouldContainsValue() {
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

     func testHeaders_whenSameKeysWithCaseDifference_shouldObtainSameValue() {
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

     func testHeaders_whenMultipleKeys_shouldIterateOverThem() {
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

     func testHeaders_whenBuildWithValues_shouldBeEqualAfterInstanciateWithHTTPHeaders() {
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

     func testHeaders_whenContainsStructureValue() {
         // Given
         let key = "Content-Type"
         let value = "application/x-www-form-urlencoded; charset=utf-8"

         // When
         headers.set(name: key, value: value)

         // Then
         XCTAssertTrue(headers.contains(value, for: key))
     }

     func testHeaders_whenInitWithTuples() {
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

     func testHeaders_whenHashable() {
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
