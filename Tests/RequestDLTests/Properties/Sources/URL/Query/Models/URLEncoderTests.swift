/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

// swiftlint:disable file_length type_body_length
class URLEncoderTests: XCTestCase {

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
        try XCTUnwrap(urlEncoder).encode(value, forKey: key)
            .map { $0.build() }
            .joined()
    }

    // MARK: - Default

    func testEncoder_whenInteger() throws {
        // Given
        let key = "foo"
        let value = 123

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(value)")
    }

    func testEncoder_whenString() throws {
        // Given
        let key = "foo"
        let value = "bar"

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(value)")
    }

    // MARK: - Optional

    func testEncoder_whenSomeWithLiteral() throws {
        // Given
        let key = "foo"
        let value = "bar"

        // When
        let sut = try encode(value as String?, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(value)")
    }

    func testEncoder_whenNoneWithLiteral() throws {
        // Given
        let key = "foo"

        // When
        let sut = try encode(String?.none, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=nil")
    }

    func testEncoder_whenSomeWithDroppingKey() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = "bar"

        urlEncoder.optionalEncodingStrategy = .droppingKey

        // When
        let sut = try encode(value as String?, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(value)")
    }

    func testEncoder_whenNoneWithDroppingKey() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"

        urlEncoder.optionalEncodingStrategy = .droppingKey

        // When
        let sut = try encode(String?.none, forKey: key)

        // Then
        XCTAssertEqual(sut, "")
    }

    func testEncoder_whenSomeWithDroppingValue() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)
        
        let key = "foo"
        let value = "bar"

        urlEncoder.optionalEncodingStrategy = .droppingValue

        // When
        let sut = try encode(value as String?, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(value)")
    }

    func testEncoder_whenNoneWithDroppingValue() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"

        urlEncoder.optionalEncodingStrategy = .droppingValue

        // When
        let sut = try encode(String?.none, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=")
    }

    func testEncoder_whenSomeWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = "bar"

        urlEncoder.optionalEncodingStrategy = .custom {
            var container = $0.valueContainer()
            try container.encode("none")
        }

        // When
        let sut = try encode(value as String?, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(value)")
    }

    func testEncoder_whenNoneWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"

        urlEncoder.optionalEncodingStrategy = .custom {
            var container = $0.valueContainer()
            try container.encode("none")
        }

        // When
        let sut = try encode(String?.none, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=none")
    }

    // MARK: - Flag

    func testEncoder_whenTrueWithLiteral() throws {
        // Given
        let key = "foo"
        let value = true

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(value)")
    }

    func testEncoder_whenFalseWithLiteral() throws {
        // Given
        let key = "foo"
        let value = false

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(value)")
    }

    func testEncoder_whenTrueWithNumeric() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = true

        urlEncoder.boolEncodingStrategy = .numeric

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=1")
    }

    func testEncoder_whenFalseWithNumeric() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = false

        urlEncoder.boolEncodingStrategy = .numeric

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=0")
    }

    func testEncoder_whenTrueWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = true

        urlEncoder.boolEncodingStrategy = .custom {
            var container = $1.valueContainer()
            try container.encode($0 ? "T" : "F")
        }

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=T")
    }

    func testEncoder_whenFalseWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = false

        urlEncoder.boolEncodingStrategy = .custom {
            var container = $1.valueContainer()
            try container.encode($0 ? "T" : "F")
        }

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=F")
    }

    // MARK: - Date
    func testEncoder_whenDateWithSecondsSince1970() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let date = Date()

        urlEncoder.dateEncodingStrategy = .secondsSince1970

        // When
        let sut = try encode(date, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(Int64(date.timeIntervalSince1970))")
    }

    func testEncoder_whenDateWithMillisecondsSince1970() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let date = Date()

        urlEncoder.dateEncodingStrategy = .millisecondsSince1970

        // When
        let sut = try encode(date, forKey: key)

        // Then
        XCTAssertEqual(sut, "\(key)=\(Int64(date.timeIntervalSince1970) * 1_000)")
    }

    func testEncoder_whenDateWithISO8601() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let date = Date()
        let dateFormatter = ISO8601DateFormatter()

        urlEncoder.dateEncodingStrategy = .iso8601

        // When
        let sut = try encode(date, forKey: key)

        // Then
        let expectedDate = dateFormatter.string(from: date)

        XCTAssertEqual(sut, "\(key)=\(expectedDate.addingRFC3986PercentEncoding())")
    }

    func testEncoder_whenDateWithDateFormatter() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let date = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd"

        urlEncoder.dateEncodingStrategy = .formatter(dateFormatter)

        // When
        let sut = try encode(date, forKey: key)

        // Then
        let expectedDate = dateFormatter.string(from: date)

        XCTAssertEqual(sut, "\(key)=\(expectedDate.addingRFC3986PercentEncoding())")
    }

    func testEncoder_whenDateWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let date = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd"

        urlEncoder.dateEncodingStrategy = .formatter(dateFormatter)

        // When
        let sut = try encode(date, forKey: key)

        // Then
        let expectedDate = dateFormatter.string(from: date)

        XCTAssertEqual(sut, "\(key)=\(expectedDate.addingRFC3986PercentEncoding())")
    }

    // MARK: - Array

    func testEncoder_whenArrayWithDroppingIndex() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .droppingIndex

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, value.map {
            "\(key)=\($0)"
        }.joined(separator: "&"))
    }

    func testEncoder_whenArrayWithSubscripted() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .subscripted

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, value.enumerated().map {
            let key = "\(key)[\($0)]".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.joined(separator: "&"))
    }

    func testEncoder_whenArrayWithAccessMember() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .accessMember

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, value.enumerated().map {
            "\(key).\($0)=\($1)"
        }.joined(separator: "&"))
    }

    func testEncoder_whenArrayWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .custom {
            var container = $1.keyContainer()
            try container.encode("@\($0)")
        }

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, value.enumerated().map {
            let key = "\(key)@\($0)".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.joined(separator: "&"))
    }

    func testEncoder_whenHeterogeneousArrayWithDroppingIndex() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

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

        XCTAssertEqual(sut, expectedString)
    }

    // MARK: - Dictionary

    func testEncoder_whenDictionaryWithSubscripted() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

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
        XCTAssertEqual(sut.count, value.count)

        XCTAssertEqual(sut.sorted(), value.map {
            let key = "\(key)[\($0)]".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.sorted())
    }

    func testEncoder_whenDictionaryWithAccessMember() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

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
        XCTAssertEqual(sut.count, value.count)

        XCTAssertEqual(sut.sorted(), value.map {
            let key = "\(key).\($0)".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.sorted())
    }

    func testEncoder_whenDictionaryWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

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
        XCTAssertEqual(sut.count, value.count)

        XCTAssertEqual(sut.sorted(), value.map {
            let key = "\(key)@\($0)".addingRFC3986PercentEncoding()
            return "\(key)=\($1)"
        }.sorted())
    }

    func testEncoder_whenHeterogeneousDictionaryWithDroppingIndex() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

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

        XCTAssertEqual(sut.count, expectedValue.count)

        XCTAssertEqual(sut.sorted(), expectedValue.map {
            let key = "\(key).\($0)".addingRFC3986PercentEncoding()
            return "\(key)=\($1.addingRFC3986PercentEncoding())"
        }.sorted())
    }

    // MARK: - Data

    func testEncoder_whenDataWithBase64() throws {
        // Given
        let key = "foo"
        let value = Data.randomData(length: 64)

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedValue = value
            .base64EncodedString()
            .addingRFC3986PercentEncoding()

        XCTAssertEqual(sut, "\(key)=\(expectedValue)")
    }

    func testEncoder_whenDataWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

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

        XCTAssertEqual(sut, "\(key)=\(expectedValue)")
    }

    // MARK: - Key

    func testEncoder_whenKeyWithLiteral() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .literal

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "oneTwo[threeFour]".addingRFC3986PercentEncoding()

        XCTAssertEqual(sut, "\(expectedKey)=1")
    }

    func testEncoder_whenKeyWithSnakeCased() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "_oneTwo_"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .snakeCased

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "_one_two_[three_four]".addingRFC3986PercentEncoding()

        XCTAssertEqual(sut, "\(expectedKey)=1")
    }

    func testEncoder_whenKeyWithKebabCased() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .kebabCased

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "one-two[three-four]".addingRFC3986PercentEncoding()

        XCTAssertEqual(sut, "\(expectedKey)=1")
    }

    func testEncoder_whenKeyWithCapitalized() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .capitalized

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "OneTwo[ThreeFour]".addingRFC3986PercentEncoding()

        XCTAssertEqual(sut, "\(expectedKey)=1")
    }

    func testEncoder_whenKeyWithUppercased() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .uppercased

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "ONETWO[THREEFOUR]".addingRFC3986PercentEncoding()

        XCTAssertEqual(sut, "\(expectedKey)=1")
    }

    func testEncoder_whenKeyWithLowercased() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .lowercased

        // When
        let sut = try encode(value, forKey: key)

        // Then
        let expectedKey = "onetwo[threefour]".addingRFC3986PercentEncoding()

        XCTAssertEqual(sut, "\(expectedKey)=1")
    }

    func testEncoder_whenKeyWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

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

        XCTAssertEqual(sut, "\(expectedKey)=1")
    }

    // MARK: - Whitespace
    func testEncoder_whenWhitespaceWithPercentEscaping() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo bar"
        let value = "one two three"

        urlEncoder.whitespaceEncodingStrategy = .percentEscaping

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "foo%20bar=one%20two%20three")
    }

    func testEncoder_whenWhitespaceWithPlus() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)

        let key = "foo bar"
        let value = "one two three"

        urlEncoder.whitespaceEncodingStrategy = .plus

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "foo+bar=one+two+three")
    }

    func testEncoder_whenWhitespaceWithCustom() throws {
        // Given
        let urlEncoder = try XCTUnwrap(urlEncoder)
        
        let key = "foo bar"
        let value = "one two three"

        urlEncoder.whitespaceEncodingStrategy = .custom {
            $0.whitespaceRepresentable = ""
        }

        // When
        let sut = try encode(value, forKey: key)

        // Then
        XCTAssertEqual(sut, "foobar=onetwothree")
    }
}
// swiftlint:enable file_length type_body_length
