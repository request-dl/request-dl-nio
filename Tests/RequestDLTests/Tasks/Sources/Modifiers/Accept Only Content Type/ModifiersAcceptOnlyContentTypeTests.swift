//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct ModifiersAcceptOnlyContentTypeTests {

    @Test
    func exactMatchIsAccepted() async throws {
        // Given / When
        let result = try await MockedTask(
            headers: ["Content-Type": "application/json"],
            content: { BaseURL("localhost") }
        )
        .collectData()
        .acceptOnlyContentType(.json)
        .result()

        // Then
        #expect(result.head.headers.first(name: "Content-Type") == "application/json")
    }

    @Test
    func charsetParameterIsIgnored() async throws {
        // Given / When
        let result = try await MockedTask(
            headers: ["Content-Type": "application/json; charset=utf-8"],
            content: { BaseURL("localhost") }
        )
        .collectData()
        .acceptOnlyContentType(.json)
        .result()

        // Then
        #expect(result.head.headers.first(name: "Content-Type") == "application/json; charset=utf-8")
    }

    @Test
    func subtypeWildcardIsAccepted() async throws {
        // Given / When
        let result = try await MockedTask(
            headers: ["Content-Type": "image/png"],
            content: { BaseURL("localhost") }
        )
        .collectData()
        .acceptOnlyContentType("image/*")
        .result()

        // Then
        #expect(result.head.headers.first(name: "Content-Type") == "image/png")
    }

    @Test
    func fullWildcardIsAccepted() async throws {
        // Given / When
        let result = try await MockedTask(
            headers: ["Content-Type": "text/html"],
            content: { BaseURL("localhost") }
        )
        .collectData()
        .acceptOnlyContentType("*/*")
        .result()

        // Then
        #expect(result.head.headers.first(name: "Content-Type") == "text/html")
    }

    @Test
    func emptyContentTypesAcceptsAnyResponse() async throws {
        // Given / When
        let result = try await MockedTask(
            headers: ["Content-Type": "text/html"],
            content: { BaseURL("localhost") }
        )
        .collectData()
        .acceptOnlyContentType([])
        .result()

        // Then
        #expect(result.head.headers.first(name: "Content-Type") == "text/html")
    }

    @Test
    func mismatchedContentTypeThrows() async throws {
        // Given
        var thrown: UnacceptableContentTypeError<TaskResult<Data>>?

        // When
        do {
            _ = try await MockedTask(
                headers: ["Content-Type": "text/html"],
                content: { BaseURL("localhost") }
            )
            .collectData()
            .acceptOnlyContentType(.json)
            .result()
        } catch let error as UnacceptableContentTypeError<TaskResult<Data>> {
            thrown = error
        }

        // Then
        #expect(thrown?.data.head.headers.first(name: "Content-Type") == "text/html")
    }

    @Test
    func missingContentTypeThrows() async throws {
        // Given
        var thrown: UnacceptableContentTypeError<TaskResult<Data>>?

        // When
        do {
            _ = try await MockedTask(
                content: { BaseURL("localhost") }
            )
            .collectData()
            .acceptOnlyContentType(.json)
            .result()
        } catch let error as UnacceptableContentTypeError<TaskResult<Data>> {
            thrown = error
        }

        // Then
        #expect(thrown != nil)
    }

    @Test
    func multipleAcceptedContentTypes() async throws {
        // Given / When
        let result = try await MockedTask(
            headers: ["Content-Type": "application/xml"],
            content: { BaseURL("localhost") }
        )
        .collectData()
        .acceptOnlyContentType(.json, .xml)
        .result()

        // Then
        #expect(result.head.headers.first(name: "Content-Type") == "application/xml")
    }
}
