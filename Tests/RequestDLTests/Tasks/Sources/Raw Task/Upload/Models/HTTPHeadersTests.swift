/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct HTTPHeadersTests {

    @Test
    func headers_whenEmpty_shouldBeEmpty() throws {
        let headers = HTTPHeaders()
        #expect(headers.isEmpty)
    }

    @Test
    func headers_whenInitWithSequence() {
        // Given
        let headers = HTTPHeaders([
            ("Content-Type", "application/json"),
            ("Content-type", "application/javascript"),
            ("Content-Type", "text/html"),
            ("Accept", "audio/mp3"),
            ("Authorization", "Bearer 123")
        ])

        // Then
        #expect(headers.count == 5)
        #expect(!headers.isEmpty)

        #expect(headers.names == [
            "Content-Type", "Accept", "Authorization"
        ])

        #expect(headers.first?.name == "Content-Type")
        #expect(headers.first?.value == "application/json")

        #expect(headers.last?.name == "Authorization")
        #expect(headers.last?.value == "Bearer 123")
    }

    @Test
    func headers_whenInitWithDictionaryLiteral() {
        // Given
        let headers: HTTPHeaders = [
            "Content-Type": "text/html",
            "Accept": "audio/mp3"
        ]

        // Then
        #expect(headers.first?.name == "Content-Type")
        #expect(headers.first?.value == "text/html")

        #expect(headers.last?.name == "Accept")
        #expect(headers.last?.value == "audio/mp3")
    }

    @Test
    func headers_whenSetValues() throws {
        // Given
        var headers = HTTPHeaders()

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

        #expect(headers.count == 3)

        #expect(headers.names == [
            "Content-Type", "Accept", "Authorization"
        ])

        #expect(
            headersSequence.map(\.0) == expectingSequence.map(\.0)
        )

        #expect(
            headersSequence.map(\.1) == expectingSequence.map(\.1)
        )
    }

    @Test
    func headers_whenAddValues() throws {
        // Given
        var headers = HTTPHeaders()

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

        #expect(headers.count == 5)

        #expect(headers.names == [
            "Content-Type", "Accept", "Authorization"
        ])

        #expect(headersSequence.map(\.0) == expectingSequence.map(\.0))

        #expect(headersSequence.map(\.1) == expectingSequence.map(\.1))
    }

    @Test
    func headers_whenRemoveAddedValue() throws {
        // Given
        var headers = HTTPHeaders()

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
        #expect(headers.count == 2)

        #expect(headers.names == [
            "Accept", "Authorization"
        ])

        #expect(headers.map(\.value) == [
            "audio/mp3", "Bearer 123"
        ])
    }

    @Test
    func headers_whenFirstOfNames() throws {
        // Given
        var headers = HTTPHeaders()

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
        #expect(value1 == "application/json")
        #expect(value2 == "audio/mp3")
        #expect(value3 == "Bearer 123")
    }

    @Test
    func headers_whenLastOfNames() throws {
        // Given
        var headers = HTTPHeaders()

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
        #expect(value1 == "text/html")
        #expect(value2 == "audio/mp3")
        #expect(value3 == "Bearer 123")
    }

    @Test
    func headers_whenContainsName() throws {
        // Given
        var headers = HTTPHeaders()

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

        #expect((0 ..< key.count).allSatisfy {
            let index = key.index(key.startIndex, offsetBy: $0)

            let uppercased = key[key.startIndex...index]
            let lowercased = key[key.index(after: index)..<key.endIndex]

            return headers.contains(name: "\(uppercased.uppercased())\(lowercased.lowercased())")
        })

        #expect(!headers.contains(name: "Accept"))
    }

    @Test
    func headers_whenContainsNameWhere() throws {
        // Given
        var headers = HTTPHeaders()

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
        #expect(headers.contains(name: "content-type") {
            $0 == "text/html"
        })

        #expect(!headers.contains(name: "content-type") {
            $0 == "audio/mp3"
        })
    }

    @Test
    func headers_whenSubscriptByName() throws {
        // Given
        var headers = HTTPHeaders()

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
        #expect(headers["CONTENT-TYPE"] == values.map(\.1))

        #expect(headers["Accept"] == nil)
    }

    @Test
    func headers_whenMergingWithRightExclusive() throws {
        // Given
        var headers = HTTPHeaders()

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
        #expect(headers.count == 6)

        #expect(headers.names == [
            "Content-Type", "Accept", "Authorization"
        ])

        #expect(headers.map(\.value) == [
            "application/json", "application/javascript", "text/html",
            "audio/mp3", "application/xml", "Bearer 123"
        ])
    }

    @Test
    func headers_whenMergingWithLeftExclusive() throws {
        // Given
        var headers = HTTPHeaders()

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
        #expect(headers.count == 6)

        #expect(headers.names == [
            "Content-Type", "Accept", "Authorization"
        ])

        #expect(headers.map(\.value) == [
            "application/json", "application/javascript", "text/html",
            "audio/mp3", "application/xml", "Bearer 123"
        ])
    }

    @Test
    func headers_whenUsingIndices() throws {
        // Given
        var headers = HTTPHeaders()

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

        #expect(value0.name == values[0].0)

        #expect(value0.value == values[0].1)

        let index1 = headers.index(after: headers.startIndex)
        let value1 = headers[index1]

        #expect(value1.name == values[0].0)

        #expect(value1.value == values[1].1)

        #expect(index1 == headers.index(headers.startIndex, offsetBy: 1))
        #expect(index1 == headers.index(headers.endIndex, offsetBy: -2))

        let index2 = headers.index(before: headers.endIndex)
        let value2 = headers[index2]

        #expect(value2.name == values[2].0)

        #expect(value2.value == values[2].1)

        #expect(index2 == headers.index(headers.startIndex, offsetBy: 2))
        #expect(index2 == headers.index(headers.endIndex, offsetBy: -1))
    }
}
