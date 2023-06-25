/*
 See LICENSE for this package's licensing information.
 */

import XCTest
@testable import RequestDL

class AcceptCharsetHeaderTests: XCTestCase {

    func testCharset_whenUTF8() async throws {
        // Given
        let charset = Charset.utf8

        // When
        let resolved = try await resolve(TestProperty {
            AcceptCharsetHeader(charset)
        })

        // Then
        XCTAssertEqual(resolved.request.headers["Accept-Charset"], [charset.rawValue])
    }

    func testCharset_whenUTF16() async throws {
        // Given
        let charset = Charset.utf16

        // When
        let resolved = try await resolve(TestProperty {
            AcceptCharsetHeader(charset)
        })

        // Then
        XCTAssertEqual(resolved.request.headers["Accept-Charset"], [charset.rawValue])
    }

    func testCharset_whenUTF32() async throws {
        // Given
        let charset = Charset.utf32

        // When
        let resolved = try await resolve(TestProperty {
            AcceptCharsetHeader(charset)
        })

        // Then
        XCTAssertEqual(resolved.request.headers["Accept-Charset"], [charset.rawValue])
    }
}
