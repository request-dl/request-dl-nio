//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONEncoder
#endif

struct ModifiersDecodeIfPresentTests {

    struct MockModel: Codable, Equatable {
        let id: Int
    }

    @Test
    func emptyBodyDecodesAsNil() async throws {
        // Given / When
        let result = try await MockedTask(
            status: .init(code: 204, reason: "No Content"),
            content: {
                BaseURL("localhost")
                Payload(data: Data())
            }
        )
        .collectData()
        .extractPayload()
        .decodeIfPresent(MockModel.self)
        .result()

        // Then
        #expect(result == nil)
    }

    @Test
    func missingPayloadDecodesAsNil() async throws {
        // Given / When
        let result = try await MockedTask(
            status: .init(code: 205, reason: "Reset Content"),
            content: { BaseURL("localhost") }
        )
        .collectData()
        .extractPayload()
        .decodeIfPresent(MockModel.self)
        .result()

        // Then
        #expect(result == nil)
    }

    @Test
    func nonEmptyBodyDecodesTheValue() async throws {
        // Given
        let mock = MockModel(id: 42)
        let data = try JSONEncoder().encode(mock)

        // When
        let result = try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .collectData()
        .extractPayload()
        .decodeIfPresent(MockModel.self)
        .result()

        // Then
        #expect(result == mock)
    }

    @Test
    func invalidNonEmptyBodyStillThrows() async throws {
        // Given
        var thrown = false

        // When
        do {
            _ = try await MockedTask(content: {
                BaseURL("localhost")
                Payload(data: Data("not json".utf8))
            })
            .collectData()
            .extractPayload()
            .decodeIfPresent(MockModel.self)
            .result()
        } catch is DecodingError {
            thrown = true
        }

        // Then
        #expect(thrown)
    }

    @Test
    func preservesTaskResultHeadWhenEmpty() async throws {
        // Given / When
        let result = try await MockedTask(
            status: .init(code: 204, reason: "No Content"),
            content: {
                BaseURL("localhost")
                Payload(data: Data())
            }
        )
        .collectData()
        .decodeIfPresent(MockModel.self)
        .result()

        // Then
        #expect(result.head.status.code == 204)
        #expect(result.payload == nil)
    }
}
