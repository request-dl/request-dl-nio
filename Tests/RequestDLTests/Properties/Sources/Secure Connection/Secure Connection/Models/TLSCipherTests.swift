/*
 See LICENSE for this package's licensing information.
 */

import XCTest
@testable import RequestDL

@RequestActor
class TLSCipherTests: XCTestCase {

    func testCipher_TLS_RSA_WITH_AES_128_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_RSA_WITH_AES_128_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_RSA_WITH_AES_128_CBC_SHA)
    }

    func testCipher_TLS_RSA_WITH_AES_256_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_RSA_WITH_AES_256_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_RSA_WITH_AES_256_CBC_SHA)
    }

    func testCipher_TLS_PSK_WITH_AES_128_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_PSK_WITH_AES_128_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_PSK_WITH_AES_128_CBC_SHA)
    }

    func testCipher_TLS_PSK_WITH_AES_256_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_PSK_WITH_AES_256_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_PSK_WITH_AES_256_CBC_SHA)
    }

    func testCipher_TLS_RSA_WITH_AES_128_GCM_SHA256() {
        // Given
        let cipher = TLSCipher.TLS_RSA_WITH_AES_128_GCM_SHA256

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_RSA_WITH_AES_128_GCM_SHA256)
    }

    func testCipher_TLS_RSA_WITH_AES_256_GCM_SHA384() {
        // Given
        let cipher = TLSCipher.TLS_RSA_WITH_AES_256_GCM_SHA384

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_RSA_WITH_AES_256_GCM_SHA384)
    }

    func testCipher_TLS_AES_128_GCM_SHA256() {
        // Given
        let cipher = TLSCipher.TLS_AES_128_GCM_SHA256

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_AES_128_GCM_SHA256)
    }

    func testCipher_TLS_AES_256_GCM_SHA384() {
        // Given
        let cipher = TLSCipher.TLS_AES_256_GCM_SHA384

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_AES_256_GCM_SHA384)
    }

    func testCipher_TLS_CHACHA20_POLY1305_SHA256() {
        // Given
        let cipher = TLSCipher.TLS_CHACHA20_POLY1305_SHA256

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_CHACHA20_POLY1305_SHA256)
    }

    func testCipher_TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA)
    }

    func testCipher_TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA)
    }

    func testCipher_TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA)
    }

    func testCipher_TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA)
    }

    func testCipher_TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA)
    }

    func testCipher_TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA)
    }

    func testCipher_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256)
    }

    func testCipher_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384)
    }

    func testCipher_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256)
    }

    func testCipher_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384)
    }

    func testCipher_TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256)
    }

    func testCipher_TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256() {
        // Given
        let cipher = TLSCipher.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256

        // When
        let sut = cipher.build()

        // Then
        XCTAssertEqual(sut, .TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256)
    }
}
