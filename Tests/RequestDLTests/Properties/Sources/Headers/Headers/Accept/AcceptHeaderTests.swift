/*
 See LICENSE for this package's licensing information.
 */

import Foundation
import Testing
@testable import RequestDL

struct AcceptHeaderTests {

    @Test
    func headersJsonAccept() async throws {
        let property = TestProperty(AcceptHeader(.json))
        let resolved = try await resolve(property)

        #expect(
            resolved.request.headers["Accept"] == ["application/json"]
        )
    }

    @Test
    func headersXmlAccept() async throws {
        let property = TestProperty(AcceptHeader(.xml))
        let resolved = try await resolve(property)

        #expect(
            resolved.request.headers["Accept"] == ["application/xml"]
        )
    }

    @Test
    func headersFormDataAccept() async throws {
        let property = TestProperty(AcceptHeader(.formData))
        let resolved = try await resolve(property)

        #expect(
            resolved.request.headers["Accept"] == ["form-data"]
        )
    }

    @Test
    func headersFormURLEncodedAccept() async throws {
        let property = TestProperty(AcceptHeader(.formURLEncoded))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["application/x-www-form-urlencoded"]
        )
    }

    @Test
    func headersTextAccept() async throws {
        let property = TestProperty(AcceptHeader(.text))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["text/plain"]
        )
    }

    @Test
    func headersHtmlAccept() async throws {
        let property = TestProperty(AcceptHeader(.html))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["text/html"]
        )
    }

    @Test
    func headersCssAccept() async throws {
        let property = TestProperty(AcceptHeader(.css))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["text/css"]
        )
    }

    @Test
    func headersJavascriptAccept() async throws {
        let property = TestProperty(AcceptHeader(.javascript))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["text/javascript"]
        )
    }

    @Test
    func headersGifAccept() async throws {
        let property = TestProperty(AcceptHeader(.gif))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["image/gif"]
        )
    }

    @Test
    func headersPngAccept() async throws {
        let property = TestProperty(AcceptHeader(.png))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["image/png"]
        )
    }

    @Test
    func headersJpegAccept() async throws {
        let property = TestProperty(AcceptHeader(.jpeg))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["image/jpeg"]
        )
    }

    @Test
    func headersBmpAccept() async throws {
        let property = TestProperty(AcceptHeader(.bmp))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["image/bmp"]
        )
    }

    @Test
    func headersWebpAccept() async throws {
        let property = TestProperty(AcceptHeader(.webp))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["image/webp"]
        )
    }

    @Test
    func headersMidiAccept() async throws {
        let property = TestProperty(AcceptHeader(.midi))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["audio/midi"]
        )
    }

    @Test
    func headersMpegAccept() async throws {
        let property = TestProperty(AcceptHeader(.mpeg))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["audio/mpeg"]
        )
    }

    @Test
    func headersWavAccept() async throws {
        let property = TestProperty(AcceptHeader(.wav))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["audio/wav"]
        )
    }

    @Test
    func headersPdfAccept() async throws {
        let property = TestProperty(AcceptHeader(.pdf))
        let resolved = try await resolve(property)
        #expect(
            resolved.request.headers["Accept"] == ["application/pdf"]
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = AcceptHeader(.json)

        // Then
        try await assertNever(property.body)
    }
}
