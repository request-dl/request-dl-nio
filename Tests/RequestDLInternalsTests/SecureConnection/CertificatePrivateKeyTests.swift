/*
 See LICENSE for this package's licensing information.
*/

#if os(macOS) || os(Linux)
import XCTest
import NIOSSL
import _RequestDLExtensions
@testable import RequestDLInternals

class CertificatePrivateKeyTests: XCTestCase {

    func testPrivate_whenPEM_shouldBeValid() async throws {
        // Given
        let openSSL = try OpenSSL().certificate()
        let data = try Data(contentsOf: openSSL.privateKeyURL)

        // When
        let resolved = try PrivateKey(Array(data), format: .pem).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .pem))
    }

    func testPrivate_whenDER_shouldBeValid() async throws {
        // Given
        let openSSL = try OpenSSL(format: .der).certificate()

        let data = try Data(contentsOf: openSSL.privateKeyURL)

        // When
        let resolved = try PrivateKey(Array(data), format: .der).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .der))
    }

    func testPrivate_whenPEMWithPassword_shouldBeValid() async throws {
        // Given
        let password = "password123"
        let openSSL = try OpenSSL(with: [.privateKey(password)]).certificate()

        let data = try Data(contentsOf: openSSL.privateKeyURL)

        // When
        let resolved = try PrivateKey(Array(data), format: .pem) {
            $0(Array(Data(password.utf8)))
        }.build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .pem) {
            $0(Array(Data(password.utf8)))
        })
    }

    func testPrivate_whenDERWithPassword_shouldBeValid() async throws {
        // Given
        let password = "password123"
        let openSSL = try OpenSSL(format: .der, with: [.privateKey(password)]).certificate()

        let data = try Data(contentsOf: openSSL.privateKeyURL)

        // When
        let resolved = try PrivateKey(Array(data), format: .der) {
            $0(Array(Data(password.utf8)))
        }.build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .der) {
            $0(Array(Data(password.utf8)))
        })
    }
}
#endif
