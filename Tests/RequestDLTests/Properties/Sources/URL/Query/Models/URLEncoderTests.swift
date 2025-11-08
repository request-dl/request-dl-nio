/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

// swiftlint:disable file_length type_body_length
struct URLEncoderTests {

    var urlEncoder: URLEncoder?

    override func setUp() async throws {
        try await super.setUp()
        urlEncoder = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        urlEncoder = nil
    }

    private func encode<Value>(_ value: Value, forKey key: String) throws -> String {
        try #require(urlEncoder).encode(value, forKey: key)
            .map { $0.build() }
            .joined()
    }

    // MARK: - Default

    @Test
    func encoder_whenInteger() throws {
        // Given
        let key = "foo"
        let value = 123

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenString() throws {
        // Given
        let key = "foo"
        let value = "bar"

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    // MARK: - Optional

    @Test
    func encoder_whenSomeWithLiteral() throws {
        // Given
        let key = "foo"
        let value = "bar"

        // When
        let sut = try encode(value as String?, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenNoneWithLiteral() throws {
        // Given
        let key = "foo"

        // When
        let sut = try encode(String?.none, forKey: key)

        // Then
        #expect(sut == "\(key)=nil")
    }

    @Test
    func encoder_whenSomeWithDroppingKey() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = "bar"

        urlEncoder.optionalEncodingStrategy = .droppingKey

        // When
        let sut = try encode(value as String?, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenNoneWithDroppingKey() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"

        urlEncoder.optionalEncodingStrategy = .droppingKey

        // When
        let sut = try encode(String?.none, forKey: key)

        // Then
        #expect(sut == "")
    }

    @Test
    func encoder_whenSomeWithDroppingValue() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = "bar"

        urlEncoder.optionalEncodingStrategy = .droppingValue

        // When
        let sut = try encode(value as String?, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenNoneWithDroppingValue() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"

        urlEncoder.optionalEncodingStrategy = .droppingValue

        // When
        let sut = try encode(String?.none, forKey: key)

        // Then
        #expect(sut == "\(key)=")
    }

    @Test
    func encoder_whenSomeWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = "bar"

        urlEncoder.optionalEncodingStrategy = .custom {
            var container = $0.valueContainer()
            try container.encode("none")
        }

        // When
        let sut = try encode(value as String?, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenNoneWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"

        urlEncoder.optionalEncodingStrategy = .custom {
            var container = $0.valueContainer()
            try container.encode("none")
        }

        // When
        let sut = try encode(String?.none, forKey: key)

        // Then
        #expect(sut == "\(key)=none")
    }

    // MARK: - Flag

    @Test
    func encoder_whenTrueWithLiteral() throws {
        // Given
        let key = "foo"
        let value = true

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenFalseWithLiteral() throws {
        // Given
        let key = "foo"
        let value = false

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenTrueWithNumeric() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = true

        urlEncoder.boolEncodingStrategy = .numeric

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=1")
    }

    @Test
    func encoder_whenFalseWithNumeric() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = false

        urlEncoder.boolEncodingStrategy = .numeric

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=0")
    }

    @Test
    func encoder_whenTrueWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = true

        urlEncoder.boolEncodingStrategy = .custom {
            var container = $1.valueContainer()
            try container.encode($0 ? "T" : "F")
        }

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=T")
    }

    @Test
    func encoder_whenFalseWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = false

        urlEncoder.boolEncodingStrategy = .custom {
            var container = $1.valueContainer()
            try container.encode($0 ? "T" : "F")
        }

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=F")
    }

    // MARK: - Date
    @Test
    func encoder_whenDateWithSecondsSince1970() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let date = Date()

        urlEncoder.dateEncodingStrategy = .secondsSince1970

        // When
        let sut = try encode(date, forKey: key)

        // Then
        #expect(sut == "\(key)=\(Int64(date.timeIntervalSince1970))")
    }

    @Test
    func encoder_whenDateWithMillisecondsSince1970() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let date = Date()

        urlEncoder.dateEncodingStrategy = .millisecondsSince1970

        // When
        let sut = try encode(date, forKey: key)

        // Then
        #expect(sut == "\(key)=\(Int64(date.timeIntervalSince1970) * 1_000)")
    }

    @Test
    func encoder_whenDateWithISO8601() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let date = Date()
        let dateFormatter = ISO8601DateFormatter()

        urlEncoder.dateEncodingStrategy = .iso8601

        // When
        let sut = try encode(date, forKey: key)

        // Then
        let expectedDate = dateFormatter.string(from: date)

        #expect(sut == "\(key)=\(expectedDate.addingRFC3986PercentEncoding())")
    }

    @Test
    func encoder_whenDateWithDateFormatter() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let date = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd"

        urlEncoder.dateEncodingStrategy = .formatter(dateFormatter)

        // When
        let sut = try encode(date, forKey: key)

        // Then
        let expectedDate = dateFormatter.string(from: date)

        #expect(sut == "\(key)=\(expectedDate.addingRFC3986PercentEncoding())")
    }

    @Test
    func encoder_whenDateWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let date = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd"

        urlEncoder.dateEncodingStrategy = .formatter(dateFormatter)

        // When
        let sut = try encode(date, forKey: key)

        // Then
        let expectedDate = dateFormatter.string(from: date)

        #expect(sut == "\(key)=\(expectedDate.addingRFC3986PercentEncoding())")
    }

    // MARK: - Array

    @Test
    func encoder_whenArrayWithDroppingIndex() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .droppingIndex

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == value.map {
            "\(key)=\($0)"
        }.joined(separator: "&"))
    }

    @Test
    func encoder_whenArrayWithSubscripted() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .subscripted

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == value.enumerated().map {
            let key = "\(key)[\($0)]".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.joined(separator: "&"))
    }

    @Test
    func encoder_whenArrayWithAccessMember() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .accessMember

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == value.enumerated().map {
            "\(key).\($0)=\($1)"
        }.joined(separator: "&"))
    }

    @Test
    func encoder_whenArrayWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .custom {
            var container = $1.keyContainer()
            try container.encode("@\($0)")
        }

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == value.enumerated().map {
            let key = "\(key)@\($0)".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.joined(separator: "&"))
    }

    @Test
    func encoder_whenHeterogeneousArrayWithDroppingIndex() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let date = Date()
        let value: [Any?] = [1, "hello", date, true, String?.none]

        let dateFormatter = ISO8601DateFormatter()

        urlEncoder.dateEncodingStrategy = .iso8601
        urlEncoder.boolEncodingStrategy = .numeric
        urlEncoder.optionalEncodingStrategy = .droppingKey
        urlEncoder.arrayEncodingStrategy = .droppingIndex

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedString = [
            "1",
            "hello",
            dateFormatter.string(from: date),
            "1"
        ]
        .map { "foo=\($0.addingRFC3986PercentEncoding())" }
        .joined(separator: "&")

        #expect(sut == expectedString)
    }

    // MARK: - Dictionary

    @Test
    func encoder_whenDictionaryWithSubscripted() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = [
            "key1": "a",
            "key2": "ab",
            "key3": "abc",
            "key4": "abcd"
        ]

        urlEncoder.dictionaryEncodingStrategy = .subscripted

        // When
        let sut = try encode(value, forKey: key).split(separator: "&")

        // Then
        #expect(sut.count == value.count)

        #expect(sut.sorted() == value.map {
            let key = "\(key)[\($0)]".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.sorted())
    }

    @Test
    func encoder_whenDictionaryWithAccessMember() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = [
            "key1": "a",
            "key2": "ab",
            "key3": "abc",
            "key4": "abcd"
        ]

        urlEncoder.dictionaryEncodingStrategy = .accessMember

        // When
        let sut = try encode(value, forKey: key).split(separator: "&")

        // Then
        #expect(sut.count == value.count)

        #expect(sut.sorted() == value.map {
            let key = "\(key).\($0)".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.sorted())
    }

    @Test
    func encoder_whenDictionaryWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = [
            "key1": "a",
            "key2": "ab",
            "key3": "abc",
            "key4": "abcd"
        ]

        urlEncoder.dictionaryEncodingStrategy = .custom {
            var container = $1.keyContainer()
            try container.encode("@\($0)")
        }

        // When
        let sut = try encode(value, forKey: key).split(separator: "&")

        // Then
        #expect(sut.count == value.count)

        #expect(sut.sorted() == value.map {
            let key = "\(key)@\($0)".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.sorted())
    }

    @Test
    func encoder_whenHeterogeneousDictionaryWithDroppingIndex() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let date = Date()
        let array = [1, 2, 3]
        let value: [String: Any?] = [
            "numeric": 1,
            "string": "hello",
            "date": date,
            "flag": true,
            "optional": String?.none,
            "array": array
        ]

        let dateFormatter = ISO8601DateFormatter()

        urlEncoder.dateEncodingStrategy = .iso8601
        urlEncoder.boolEncodingStrategy = .numeric
        urlEncoder.optionalEncodingStrategy = .droppingKey
        urlEncoder.arrayEncodingStrategy = .accessMember
        urlEncoder.dictionaryEncodingStrategy = .accessMember

        // When
        let sut = try encode(value, forKey: key).split(separator: "&")

        // Then
        let expectedValue = [
            "numeric": "1",
            "string": "hello",
            "date": dateFormatter.string(from: date),
            "flag": "1",
            "array.0": "1",
            "array.1": "2",
            "array.2": "3"
        ]

        #expect(sut.count == expectedValue.count)

        #expect(sut.sorted() == expectedValue.map {
            let key = "\(key).\($0)".addingRFC3986PercentEncoding()
            return "\(key)=\($1.addingRFC3986PercentEncoding())"
        }.sorted())
    }

    // MARK: - Data

    @Test
    func encoder_whenDataWithBase64() throws {
        // Given
        let key = "foo"
        let value = Data.randomData(length: 64)

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedValue = value
            .base64EncodedString()
            .addingRFC3986PercentEncoding()

        #expect(sut == "\(key)=\(expectedValue)")
    }

    @Test
    func encoder_whenDataWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo"
        let value = Data.randomData(length: 64)

        urlEncoder.dataEncodingStrategy = .custom {
            var container = $1.valueContainer()
            try container.encode($0.map { String($0) }.joined())
        }
        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedValue = value.map { String($0) }.joined()

        #expect(sut == "\(key)=\(expectedValue)")
    }

    // MARK: - Key

    @Test
    func encoder_whenKeyWithLiteral() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .literal

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "oneTwo[threeFour]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithSnakeCased() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "_oneTwo_"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .snakeCased

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "_one_two_[three_four]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithKebabCased() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .kebabCased

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "one-two[three-four]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithCapitalized() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .capitalized

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "OneTwo[ThreeFour]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithUppercased() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .uppercased

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "ONETWO[THREEFOUR]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithLowercased() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .lowercased

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "onetwo[threefour]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .custom {
            var container = $1.keyContainer()
            try container.encode($0
                .splitByUppercasedCharacters()
                .joined(separator: ".")
                .lowercased()
            )
        }

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "one.two[three.four]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    // MARK: - Whitespace
    @Test
    func encoder_whenWhitespaceWithPercentEscaping() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo bar"
        let value = "one two three"

        urlEncoder.whitespaceEncodingStrategy = .percentEscaping

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "foo%20bar=one%20two%20three")
    }

    @Test
    func encoder_whenWhitespaceWithPlus() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo bar"
        let value = "one two three"

        urlEncoder.whitespaceEncodingStrategy = .plus

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "foo+bar=one+two+three")
    }

    @Test
    func encoder_whenWhitespaceWithCustom() throws {
        // Given
        let urlEncoder = try #require(urlEncoder)

        let key = "foo bar"
        let value = "one two three"

        urlEncoder.whitespaceEncodingStrategy = .custom {
            $0.whitespaceRepresentable = ""
        }

        // When
        let sut = try encode(value, forKey: key)

        // Then
        #expect(sut == "foobar=onetwothree")
    }
}
// swiftlint:enable file_length type_body_length
