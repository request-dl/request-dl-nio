//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct AcceptCharsetHeaderTests {

    @Test
    @available(*, deprecated)
    func charset_whenUTF8() async throws {
        // Given
        let charset = Charset.utf8

        // When
        let resolved = try await resolve(
            TestProperty {
                AcceptCharsetHeader(charset)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Accept-Charset"] == [charset.rawValue])
    }

    @Test
    @available(*, deprecated)
    func charset_whenUTF16() async throws {
        // Given
        let charset = Charset.utf16

        // When
        let resolved = try await resolve(
            TestProperty {
                AcceptCharsetHeader(charset)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Accept-Charset"] == [charset.rawValue])
    }

    @Test
    @available(*, deprecated)
    func charset_whenUTF32() async throws {
        // Given
        let charset = Charset.utf32

        // When
        let resolved = try await resolve(
            TestProperty {
                AcceptCharsetHeader(charset)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Accept-Charset"] == [charset.rawValue])
    }

    @Test
    @available(*, deprecated)
    func neverBody() async throws {
        // Given
        let property = AcceptCharsetHeader(.utf8)

        // Then
        try await assertNever(property.body)
    }
}
