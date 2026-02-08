/*
 See LICENSE for this package's licensing information.
 */

import Foundation
import Testing
@testable import RequestDL

struct AcceptCharsetHeaderTests {

    @Test
    func charset_whenUTF8() async throws {
        // Given
        let charset = Charset.utf8

        // When
        let resolved = try await resolve(TestProperty {
            AcceptCharsetHeader(charset)
        })

        // Then
        #expect(resolved.requestConfiguration.headers["Accept-Charset"] == [charset.rawValue])
    }

    @Test
    func charset_whenUTF16() async throws {
        // Given
        let charset = Charset.utf16

        // When
        let resolved = try await resolve(TestProperty {
            AcceptCharsetHeader(charset)
        })

        // Then
        #expect(resolved.requestConfiguration.headers["Accept-Charset"] == [charset.rawValue])
    }

    @Test
    func charset_whenUTF32() async throws {
        // Given
        let charset = Charset.utf32

        // When
        let resolved = try await resolve(TestProperty {
            AcceptCharsetHeader(charset)
        })

        // Then
        #expect(resolved.requestConfiguration.headers["Accept-Charset"] == [charset.rawValue])
    }
}
