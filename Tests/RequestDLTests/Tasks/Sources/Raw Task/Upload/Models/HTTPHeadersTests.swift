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

        XCTAssertEqual(headers.names, [
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

        XCTAssertEqual(headers.names, [
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

        XCTAssertEqual(headers.names, [
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

        XCTAssertEqual(headers.names, [
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

        XCTAssertEqual(headers.names, [
            "Content-Type", "Accept", "Authorization"
        ])

        XCTAssertEqual(headers.map(\.value), [
            "application/json", "application/javascript", "text/html",
            "audio/mp3", "application/xml", "Bearer 123"
        ])
    }

    func testHeaders_whenMergingWithLeftExclusive() {
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

        let otherHeaders = HTTPHeaders(sharedValues)

        // When
        for (name, value) in sharedValues + exclusiveValues {
            headers.add(name: name, value: value)
        }

        headers = headers.merging(otherHeaders, by: +)

        // Then
        XCTAssertEqual(headers.count, 6)

        XCTAssertEqual(headers.names, [
            "Content-Type", "Accept", "Authorization"
        ])

        XCTAssertEqual(headers.map(\.value), [
            "application/json", "application/javascript", "text/html",
            "audio/mp3", "application/xml", "Bearer 123"
        ])
    }

    func testHeaders_whenUsingIndices() {
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
        let value0 = headers[headers.startIndex]

        XCTAssertEqual(
            value0.name,
            values[0].0
        )

        XCTAssertEqual(
            value0.value,
            values[0].1
        )

        let index1 = headers.index(after: headers.startIndex)
        let value1 = headers[index1]

        XCTAssertEqual(
            value1.name,
            values[0].0
        )

        XCTAssertEqual(
            value1.value,
            values[1].1
        )

        XCTAssertEqual(index1, headers.index(headers.startIndex, offsetBy: 1))
        XCTAssertEqual(index1, headers.index(headers.endIndex, offsetBy: -2))

        let index2 = headers.index(before: headers.endIndex)
        let value2 = headers[index2]

        XCTAssertEqual(
            value2.name,
            values[2].0
        )

        XCTAssertEqual(
            value2.value,
            values[2].1
        )

        XCTAssertEqual(index2, headers.index(headers.startIndex, offsetBy: 2))
        XCTAssertEqual(index2, headers.index(headers.endIndex, offsetBy: -1))
    }
}

@available(*, deprecated)
extension HTTPHeadersTests {

    func testHeaders_whenInitWithDictionary() {
        // Given
        let dictionary = [
            "Content-Type": "text/html",
            "Accept": "audio/mp3"
        ]

        let headers = HTTPHeaders(dictionary)

        // Then
        let sequence = Array(dictionary)

        XCTAssertEqual(headers.first?.name, sequence.first?.key)
        XCTAssertEqual(headers.first?.value, sequence.first?.value)

        XCTAssertEqual(headers.last?.name, sequence.last?.key)
        XCTAssertEqual(headers.last?.value, sequence.last?.value)
    }

    func testHeaders_whenSetValue() {
        // Given
        let headers = [
            ("Content-Type", "text/html"),
            ("CONTENT-TYPE", "application/json"),
            ("Accept", "audio/mp3")
        ]

        // When
        for (name, value) in headers {
            self.headers.setValue(value, forKey: name)
        }

        // Then
        XCTAssertEqual(
            self.headers.getValue(forKey: "CONTENT-TYPE"),
            "application/json"
        )

        XCTAssertEqual(
            self.headers.getValue(forKey: "ACCEPT"),
            "audio/mp3"
        )
    }
}

