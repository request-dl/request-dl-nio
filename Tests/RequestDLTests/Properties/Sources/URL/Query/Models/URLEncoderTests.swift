//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.Date
#endif

struct URLEncoderTests {

    // MARK: - Default

    @Test
    func encoder_whenInteger() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = 123

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenString() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = "bar"

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    // MARK: - Optional

    @Test
    func encoder_whenSomeWithLiteral() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = "bar"

        // When
        let sut = try urlEncoder.encode(value as String?, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenNoneWithLiteral() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"

        // When
        let sut = try urlEncoder.encode(String?.none, forKey: key)

        // Then
        #expect(sut == "\(key)=nil")
    }

    @Test
    func encoder_whenSomeWithDroppingKey() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = "bar"

        urlEncoder.optionalEncodingStrategy = .droppingKey

        // When
        let sut = try urlEncoder.encode(value as String?, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenNoneWithDroppingKey() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"

        urlEncoder.optionalEncodingStrategy = .droppingKey

        // When
        let sut = try urlEncoder.encode(String?.none, forKey: key)

        // Then
        #expect(sut == "")
    }

    @Test
    func encoder_whenSomeWithDroppingValue() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = "bar"

        urlEncoder.optionalEncodingStrategy = .droppingValue

        // When
        let sut = try urlEncoder.encode(value as String?, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenNoneWithDroppingValue() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"

        urlEncoder.optionalEncodingStrategy = .droppingValue

        // When
        let sut = try urlEncoder.encode(String?.none, forKey: key)

        // Then
        #expect(sut == "\(key)=")
    }

    @Test
    func encoder_whenSomeWithCustom() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = "bar"

        urlEncoder.optionalEncodingStrategy = .custom {
            var container = $0.valueContainer()
            try container.encode("none")
        }

        // When
        let sut = try urlEncoder.encode(value as String?, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenNoneWithCustom() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"

        urlEncoder.optionalEncodingStrategy = .custom {
            var container = $0.valueContainer()
            try container.encode("none")
        }

        // When
        let sut = try urlEncoder.encode(String?.none, forKey: key)

        // Then
        #expect(sut == "\(key)=none")
    }

    // MARK: - Flag

    @Test
    func encoder_whenTrueWithLiteral() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = true

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenFalseWithLiteral() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = false

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=\(value)")
    }

    @Test
    func encoder_whenTrueWithNumeric() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = true

        urlEncoder.boolEncodingStrategy = .numeric

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=1")
    }

    @Test
    func encoder_whenFalseWithNumeric() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = false

        urlEncoder.boolEncodingStrategy = .numeric

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=0")
    }

    @Test
    func encoder_whenTrueWithCustom() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = true

        urlEncoder.boolEncodingStrategy = .custom {
            var container = $1.valueContainer()
            try container.encode($0 ? "T" : "F")
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=T")
    }

    @Test
    func encoder_whenFalseWithCustom() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = false

        urlEncoder.boolEncodingStrategy = .custom {
            var container = $1.valueContainer()
            try container.encode($0 ? "T" : "F")
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "\(key)=F")
    }

    // MARK: - Date
    @Test
    func encoder_whenDateWithSecondsSince1970() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let date = Date()

        urlEncoder.dateEncodingStrategy = .secondsSince1970

        // When
        let sut = try urlEncoder.encode(date, forKey: key)

        // Then
        #expect(sut == "\(key)=\(Int64(date.timeIntervalSince1970))")
    }

    @Test
    func encoder_whenDateWithMillisecondsSince1970() throws {
        let urlEncoder = URLEncoder()

        // Given
        let key = "foo"
        let date = Date()
        urlEncoder.dateEncodingStrategy = .millisecondsSince1970

        // When
        let sut = try urlEncoder.encode(date, forKey: key)

        // Then
        let expectedMilliseconds = Int64(date.timeIntervalSince1970 * 1000)

        #expect(sut == "\(key)=\(expectedMilliseconds)")
    }

    @Test
    func encoder_whenDateWithISO8601() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let date = Date()

        urlEncoder.dateEncodingStrategy = .iso8601

        // When
        let sut = try urlEncoder.encode(date, forKey: key)

        // Then
        let expectedDate = date.formatted(.iso8601)

        #expect(sut == "\(key)=\(expectedDate.addingRFC3986PercentEncoding())")
    }

    @Test
    func encoder_whenDateWithCustomStrategy() throws {
        let urlEncoder = URLEncoder()

        // Given
        let key = "foo"
        let date = Date()

        urlEncoder.dateEncodingStrategy = .custom { date in
            date.formatted(.iso8601)
        }

        // When
        let sut = try urlEncoder.encode(date, forKey: key)

        // Then
        let expectedDate = date.formatted(.iso8601)

        #expect(sut == "\(key)=\(expectedDate.addingRFC3986PercentEncoding())")
    }

    @Test
    func encoder_whenDateWithCustom() throws {
        let urlEncoder = URLEncoder()

        // Given
        let key = "foo"
        let date = Date()

        urlEncoder.dateEncodingStrategy = .custom { date in
            Self.yyyyMMdd(date)
        }

        // When
        let sut = try urlEncoder.encode(date, forKey: key)

        // Then
        let expectedDate = Self.yyyyMMdd(date)

        #expect(sut == "\(key)=\(expectedDate.addingRFC3986PercentEncoding())")
    }

    /// `DateFormatter` with `dateFormat = "yyyy-MM-dd"` is not an option here — it is not part
    /// of `FoundationEssentials`. Built on the same calendar arithmetic the package's own
    /// `Date.toISO8601String()` uses, so it needs no locale (a calendar year, not a week year,
    /// avoids the turn-of-year surprises a literal `"yyyy"` template is normally chosen to
    /// dodge).
    private static func yyyyMMdd(_ date: Date) -> String {
        let timestamp = Int64(date.timeIntervalSince1970.rounded(.down))
        let days = Internals.GregorianCalendar.floorDivide(timestamp, by: 86_400)
        let civil = Internals.GregorianCalendar.civilFromDays(days)
        let pad = Internals.GregorianCalendar.pad

        return pad(civil.year, 4) + "-" + pad(civil.month, 2) + "-" + pad(civil.day, 2)
    }

    // MARK: - Array

    @Test
    func encoder_whenArrayWithDroppingIndex() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .droppingIndex

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(
            sut
                == value.map {
                    "\(key)=\($0)"
                }.joined(separator: "&")
        )
    }

    @Test
    func encoder_whenArrayWithSubscripted() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .subscripted

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(
            sut
                == value.enumerated().map {
                    let key = "\(key)[\($0)]".addingRFC3986PercentEncoding()
                    return "\(key)=\($1)"
                }.joined(separator: "&")
        )
    }

    @Test
    func encoder_whenArrayWithAccessMember() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .accessMember

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(
            sut
                == value.enumerated().map {
                    "\(key).\($0)=\($1)"
                }.joined(separator: "&")
        )
    }

    @Test
    func encoder_whenArrayWithCustom() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = ["a", "ab", "abc", "abcd"]

        urlEncoder.arrayEncodingStrategy = .custom {
            var container = $1.keyContainer()
            try container.encode("@\($0)")
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(
            sut
                == value.enumerated().map {
                    let key = "\(key)@\($0)".addingRFC3986PercentEncoding()
                    return "\(key)=\($1)"
                }.joined(separator: "&")
        )
    }

    @Test
    func encoder_whenHeterogeneousArrayWithDroppingIndex() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let date = Date()
        let value: [Any?] = [1, "hello", date, true, String?.none]

        urlEncoder.dateEncodingStrategy = .iso8601
        urlEncoder.boolEncodingStrategy = .numeric
        urlEncoder.optionalEncodingStrategy = .droppingKey
        urlEncoder.arrayEncodingStrategy = .droppingIndex

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedString = [
            "1",
            "hello",
            date.formatted(.iso8601),
            "1",
        ]
        .map { "foo=\($0.addingRFC3986PercentEncoding())" }
        .joined(separator: "&")

        #expect(sut == expectedString)
    }

    // MARK: - Dictionary

    @Test
    func encoder_whenDictionaryWithSubscripted() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = [
            "key1": "a",
            "key2": "ab",
            "key3": "abc",
            "key4": "abcd",
        ]

        urlEncoder.dictionaryEncodingStrategy = .subscripted

        // When
        let sut = try urlEncoder.encode(value, forKey: key).split(separator: "&")

        // Then
        #expect(sut.count == value.count)

        #expect(
            sut.sorted()
                == value.map {
                    let key = "\(key)[\($0)]".addingRFC3986PercentEncoding()
                    return "\(key)=\($1)"
                }.sorted()
        )
    }

    @Test
    func encoder_whenDictionaryWithAccessMember() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = [
            "key1": "a",
            "key2": "ab",
            "key3": "abc",
            "key4": "abcd",
        ]

        urlEncoder.dictionaryEncodingStrategy = .accessMember

        // When
        let sut = try urlEncoder.encode(value, forKey: key).split(separator: "&")

        // Then
        #expect(sut.count == value.count)

        #expect(
            sut.sorted()
                == value.map {
                    let key = "\(key).\($0)".addingRFC3986PercentEncoding()
                    return "\(key)=\($1)"
                }.sorted()
        )
    }

    @Test
    func encoder_whenDictionaryWithCustom() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = [
            "key1": "a",
            "key2": "ab",
            "key3": "abc",
            "key4": "abcd",
        ]

        urlEncoder.dictionaryEncodingStrategy = .custom {
            var container = $1.keyContainer()
            try container.encode("@\($0)")
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key).split(separator: "&")

        // Then
        #expect(sut.count == value.count)

        #expect(
            sut.sorted()
                == value.map {
                    let key = "\(key)@\($0)".addingRFC3986PercentEncoding()
                    return "\(key)=\($1)"
                }.sorted()
        )
    }

    @Test
    func encoder_whenHeterogeneousDictionaryWithDroppingIndex() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let date = Date()
        let array = [1, 2, 3]
        let value: [String: Any?] = [
            "numeric": 1,
            "string": "hello",
            "date": date,
            "flag": true,
            "optional": String?.none,
            "array": array,
        ]

        urlEncoder.dateEncodingStrategy = .iso8601
        urlEncoder.boolEncodingStrategy = .numeric
        urlEncoder.optionalEncodingStrategy = .droppingKey
        urlEncoder.arrayEncodingStrategy = .accessMember
        urlEncoder.dictionaryEncodingStrategy = .accessMember

        // When
        let sut = try urlEncoder.encode(value, forKey: key).split(separator: "&")

        // Then
        let expectedValue = [
            "numeric": "1",
            "string": "hello",
            "date": date.formatted(.iso8601),
            "flag": "1",
            "array.0": "1",
            "array.1": "2",
            "array.2": "3",
        ]

        #expect(sut.count == expectedValue.count)

        #expect(
            sut.sorted()
                == expectedValue.map {
                    let key = "\(key).\($0)".addingRFC3986PercentEncoding()
                    return "\(key)=\($1.addingRFC3986PercentEncoding())"
                }.sorted()
        )
    }

    // MARK: - Data

    @Test
    func encoder_whenDataWithBase64() async throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = await Data.randomData(length: 64)

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedValue =
            value
            .base64EncodedString()
            .addingRFC3986PercentEncoding()

        #expect(sut == "\(key)=\(expectedValue)")
    }

    @Test
    func encoder_whenDataWithCustom() async throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo"
        let value = await Data.randomData(length: 64)

        urlEncoder.dataEncodingStrategy = .custom {
            var container = $1.valueContainer()
            try container.encode($0.map { String($0) }.joined())
        }
        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedValue = value.map { String($0) }.joined()

        #expect(sut == "\(key)=\(expectedValue)")
    }

    // MARK: - Key

    @Test
    func encoder_whenKeyWithLiteral() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .literal

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedKey = "oneTwo[threeFour]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithSnakeCased() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "_oneTwo_"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .snakeCased

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedKey = "_one_two_[three_four]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithKebabCased() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .kebabCased

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedKey = "one-two[three-four]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithCapitalized() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .capitalized

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedKey = "OneTwo[ThreeFour]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithUppercased() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .uppercased

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedKey = "ONETWO[THREEFOUR]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithLowercased() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .lowercased

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedKey = "onetwo[threefour]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    @Test
    func encoder_whenKeyWithCustom() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "oneTwo"
        let value = ["threeFour": "1"]

        urlEncoder.keyEncodingStrategy = .custom {
            var container = $1.keyContainer()
            try container.encode(
                $0
                    .splitByUppercasedCharacters()
                    .joined(separator: ".")
                    .lowercased()
            )
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        let expectedKey = "one.two[three.four]".addingRFC3986PercentEncoding()

        #expect(sut == "\(expectedKey)=1")
    }

    // MARK: - Whitespace
    @Test
    func encoder_whenWhitespaceWithPercentEscaping() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo bar"
        let value = "one two three"

        urlEncoder.whitespaceEncodingStrategy = .percentEscaping

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "foo%20bar=one%20two%20three")
    }

    @Test
    func encoder_whenWhitespaceWithPlus() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo bar"
        let value = "one two three"

        urlEncoder.whitespaceEncodingStrategy = .plus

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "foo+bar=one+two+three")
    }

    @Test
    func encoder_whenWhitespaceWithCustom() throws {
        let urlEncoder = URLEncoder()
        // Given

        let key = "foo bar"
        let value = "one two three"

        urlEncoder.whitespaceEncodingStrategy = .custom {
            $0.whitespaceRepresentable = ""
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut == "foobar=onetwothree")
    }

    @Test
    func encoder_whenWhitespaceCustomLeavesRepresentableUnset_throwsUnsetWhitespaceRepresentable() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo bar"
        let value = "one two"

        urlEncoder.whitespaceEncodingStrategy = .custom { _ in }

        // Then
        #expect {
            try urlEncoder.encode(value, forKey: key)
        } throws: {
            guard let error = $0 as? URLEncoderError else {
                return false
            }

            return error.errorType == .unsetWhitespaceRepresentable
                && error.description
                    == "The whitespace strategy did not set a representation for the space character"
        }
    }

    // MARK: - KeyContainer

    @Test
    func encoder_whenKeyDroppedWithCustom() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "secret"
        let value = "shouldNotAppear"

        urlEncoder.keyEncodingStrategy = .custom { _, encoder in
            var container = encoder.keyContainer()
            try container.dropKey()
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut.isEmpty)
    }

    @Test
    func encoder_whenKeyReadBackWithUnkeyed() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = "bar"
        let readBack = InlineProperty<String?>(wrappedValue: nil)

        urlEncoder.keyEncodingStrategy = .custom { key, encoder in
            var container = encoder.keyContainer()
            try container.encode(key.uppercased())
            readBack.wrappedValue = try container.unkeyed()
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(readBack.wrappedValue == key.uppercased())
        #expect(sut == "FOO=bar")
    }

    @Test
    func encoder_whenKeyUnkeyedBeforeEncoding_throwsUnset() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = "bar"

        urlEncoder.keyEncodingStrategy = .custom { _, encoder in
            let container = encoder.keyContainer()
            _ = try container.unkeyed()
        }

        // Then
        #expect {
            try urlEncoder.encode(value, forKey: key)
        } throws: {
            guard let error = $0 as? URLEncoderError else {
                return false
            }

            return error.errorType == .unset
                && error.description == "The URL encoding container was read before a value was written to it"
        }
    }

    @Test
    func encoder_whenKeyEncodedTwice_throwsAlreadySet() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = "bar"

        urlEncoder.keyEncodingStrategy = .custom { key, encoder in
            var container = encoder.keyContainer()
            try container.encode(key)
            try container.encode(key)
        }

        // Then
        #expect {
            try urlEncoder.encode(value, forKey: key)
        } throws: {
            guard let error = $0 as? URLEncoderError else {
                return false
            }

            return error.errorType == .alreadySet
                && error.description == "The URL encoding container was written to more than once"
        }
    }

    @Test
    func encoder_whenKeyNeverEncodedNorDropped_throwsUnset() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "foo"
        let value = "bar"

        // A custom strategy that never touches its key container at all — distinct from
        // `encoder_whenKeyUnkeyedBeforeEncoding_throwsUnset` above, which reads the container's
        // own local state back before writing to it. This instead reaches
        // `URLEncoder.Encoder.getKey()`'s own `.none` case, since nothing ever calls
        // `encoder.setKey(_:)`.
        urlEncoder.keyEncodingStrategy = .custom { _, _ in }

        // Then
        #expect {
            try urlEncoder.encode(value, forKey: key)
        } throws: {
            guard let error = $0 as? URLEncoderError else {
                return false
            }

            return error.errorType == .unset
        }
    }

    // MARK: - ValueContainer

    @Test
    func encoder_whenValueReadBackWithUnkeyed() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "flag"
        let readBack = InlineProperty<String?>(wrappedValue: nil)

        urlEncoder.boolEncodingStrategy = .custom { flag, encoder in
            var container = encoder.valueContainer()
            try container.encode(flag ? "yes" : "no")
            readBack.wrappedValue = try container.unkeyed()
        }

        // When
        let sut = try urlEncoder.encode(true, forKey: key)

        // Then
        #expect(readBack.wrappedValue == "yes")
        #expect(sut == "\(key)=yes")
    }

    @Test
    func encoder_whenValueUnkeyedBeforeEncoding_throwsUnset() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "flag"

        urlEncoder.boolEncodingStrategy = .custom { _, encoder in
            let container = encoder.valueContainer()
            _ = try container.unkeyed()
        }

        // Then
        #expect {
            try urlEncoder.encode(true, forKey: key)
        } throws: {
            guard let error = $0 as? URLEncoderError else {
                return false
            }

            return error.errorType == .unset
        }
    }

    @Test
    func encoder_whenValueNeverEncodedNorDropped_throwsUnset() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "flag"

        // Same distinction as `encoder_whenKeyNeverEncodedNorDropped_throwsUnset`: this never
        // touches the value container, reaching `URLEncoder.Encoder.getValue()`'s own `.none`
        // case rather than the container's own unwritten-local-state check.
        urlEncoder.boolEncodingStrategy = .custom { _, _ in }

        // Then
        #expect {
            try urlEncoder.encode(true, forKey: key)
        } throws: {
            guard let error = $0 as? URLEncoderError else {
                return false
            }

            return error.errorType == .unset
        }
    }

    @Test
    func encoder_whenValueEncodedTwice_throwsAlreadySet() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "flag"

        urlEncoder.boolEncodingStrategy = .custom { flag, encoder in
            var container = encoder.valueContainer()
            try container.encode(flag ? "yes" : "no")
            try container.encode(flag ? "yes" : "no")
        }

        // Then
        #expect {
            try urlEncoder.encode(true, forKey: key)
        } throws: {
            guard let error = $0 as? URLEncoderError else {
                return false
            }

            return error.errorType == .alreadySet
        }
    }

    // MARK: - Strategy getters

    @Test
    func encoder_strategyGetters_returnWhatWasSet() {
        let urlEncoder = URLEncoder()

        urlEncoder.dateEncodingStrategy = .millisecondsSince1970
        urlEncoder.keyEncodingStrategy = .uppercased
        urlEncoder.dataEncodingStrategy = .custom { _, _ in }
        urlEncoder.boolEncodingStrategy = .numeric
        urlEncoder.optionalEncodingStrategy = .droppingKey
        urlEncoder.arrayEncodingStrategy = .accessMember
        urlEncoder.dictionaryEncodingStrategy = .accessMember
        urlEncoder.whitespaceEncodingStrategy = .plus

        if case .millisecondsSince1970 = urlEncoder.dateEncodingStrategy {
        } else {
            Issue.record("Expected .millisecondsSince1970")
        }

        if case .uppercased = urlEncoder.keyEncodingStrategy {
        } else {
            Issue.record("Expected .uppercased")
        }

        if case .numeric = urlEncoder.boolEncodingStrategy {
        } else {
            Issue.record("Expected .numeric")
        }

        if case .droppingKey = urlEncoder.optionalEncodingStrategy {
        } else {
            Issue.record("Expected .droppingKey")
        }

        if case .accessMember = urlEncoder.arrayEncodingStrategy {
        } else {
            Issue.record("Expected .accessMember")
        }

        if case .accessMember = urlEncoder.dictionaryEncodingStrategy {
        } else {
            Issue.record("Expected .accessMember")
        }

        if case .plus = urlEncoder.whitespaceEncodingStrategy {
        } else {
            Issue.record("Expected .plus")
        }
    }

    // MARK: - Dropped super keys

    @Test
    func encoder_whenDictionarySuperKeyDroppedWithCustom_producesNoQueryItems() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "root"
        let value: [String: Any] = ["a": 1]

        urlEncoder.keyEncodingStrategy = .custom { _, encoder in
            var container = encoder.keyContainer()
            try container.dropKey()
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut.isEmpty)
    }

    @Test
    func encoder_whenArraySuperKeyDroppedWithCustom_producesNoQueryItems() throws {
        let urlEncoder = URLEncoder()
        // Given
        let key = "root"
        let value: [Any] = [1, 2]

        urlEncoder.keyEncodingStrategy = .custom { _, encoder in
            var container = encoder.keyContainer()
            try container.dropKey()
        }

        // When
        let sut = try urlEncoder.encode(value, forKey: key)

        // Then
        #expect(sut.isEmpty)
    }

    // MARK: - Direct recursive encode

    @Test
    func recursiveEncode_calledDirectly_usesCurrentConfiguration() throws {
        let urlEncoder = URLEncoder()
        // Given
        urlEncoder.keyEncodingStrategy = .uppercased

        // When
        let items = try urlEncoder._recursiveEncode(123, forKey: "foo")

        // Then
        #expect(items.map(\.name) == ["FOO"])
        #expect(items.map(\.value) == ["123"])
    }
}

extension URLEncoder {

    fileprivate func encode<Value>(_ value: Value, forKey key: String) throws -> String {
        try self.encode(value, forKey: key)
            .joined()
    }
}
