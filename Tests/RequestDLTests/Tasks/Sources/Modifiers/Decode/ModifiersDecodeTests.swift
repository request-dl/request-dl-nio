/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersDecodeTests {

    struct MockModel: Codable {
        let date: Date
    }

    @Test
    func arrayOfDates() async throws {
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

        let result = try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .collectData()
        .decode([Date].self, decoder: decoder)
        .extractPayload()
        .result()

        // Then
        #expect(result.map(\.seconds) == array.map(\.seconds))
    }

    @Test
    func dictionary() async throws {
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

        let result = try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .collectData()
        .decode([Date: Int].self, decoder: decoder)
        .extractPayload()
        .result()

        // Then
        #expect(result.keys.count == dictionary.keys.count)
        #expect(result.values.count == dictionary.values.count)

        func transform(_ dictionary: [Date: Int]) -> [Int: Int] {
            var transformed = [Int: Int]()

            for (key, value) in dictionary {
                transformed[Int(key.seconds)] = value
            }

            return transformed
        }

        #expect(transform(result) == transform(dictionary))
    }

    @Test
    func plainObject() async throws {
        // Given
        let mock = MockModel(date: Date())

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970

        // When
        let data = try encoder.encode(mock)

        let result = try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .collectData()
        .decode(MockModel.self, decoder: decoder)
        .extractPayload()
        .result()

        // Then
        #expect(result.date.seconds == mock.date.seconds)
    }

    @Test
    func arrayOfIntegersInData() async throws {
        // Given
        let array = Array(0..<10)

        // When
        let data = try JSONEncoder().encode(array)

        let result = try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .collectData()
        .extractPayload()
        .decode([Int].self)
        .result()

        // Then
        #expect(array == result)
    }
}
