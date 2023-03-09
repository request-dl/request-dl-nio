/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ModifiersDecodeTests: XCTestCase {

    struct MockModel: Codable {
        let date: Date
    }

    func testArrayOfDates() async throws {
        // Given
        let now = Date()
        let array = Array((0 ..< 10).map {
            Date(timeInterval: Double($0), since: now)
        })
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970

        // When
        let data = try encoder.encode(array)

        let result = try await MockedTask { data }
            .decode([Date].self, decoder: decoder)
            .extractPayload()
            .result()

        // Then
        XCTAssertEqual(
            result.map(\.timeIntervalSince1970),
            array.map(\.timeIntervalSince1970)
        )
    }

    func testDictionary() async throws {
        // Given
        let now = Date()
        var dictionary = [Date: Int]()

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970

        for index in 0 ..< 10 {
            dictionary[Date(timeInterval: Double(index), since: now)] = index
        }

        // When
        let data = try encoder.encode(dictionary)

        let result = try await MockedTask { data }
            .decode([Date: Int].self, decoder: decoder)
            .extractPayload()
            .result()

        // Then
        XCTAssertEqual(result.keys.count, dictionary.keys.count)
        XCTAssertEqual(result.values.count, dictionary.values.count)

        func transform(_ dictionary: [Date: Int]) -> [Int: Int] {
            var transformed = [Int: Int]()

            for (key, value) in dictionary {
                transformed[Int(key.timeIntervalSince1970)] = value
            }

            return transformed
        }

        XCTAssertEqual(transform(result), transform(dictionary))
    }

    func testPlainObject() async throws {
        // Given
        let mock = MockModel(date: Date())

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970

        // When
        let data = try encoder.encode(mock)

        let result = try await MockedTask { data }
            .decode(MockModel.self, decoder: decoder)
            .extractPayload()
            .result()

        // Then
        XCTAssertEqual(
            result.date.timeIntervalSince1970,
            mock.date.timeIntervalSince1970
        )
    }

    func testEmptyDictionary() async throws {
        // Given
        let emptyData = Data()

        // When
        let result = try await MockedTask { emptyData }
            .decode([Int: Int].self)
            .extractPayload()
            .result()

        // Given
        XCTAssertEqual(result, [:])
    }

    func testEmptyArray() async throws {
        // Given
        let emptyData = Data()

        // When
        let result = try await MockedTask { emptyData }
            .decode([Int].self)
            .extractPayload()
            .result()

        // Given
        XCTAssertEqual(result, [])
    }
}
