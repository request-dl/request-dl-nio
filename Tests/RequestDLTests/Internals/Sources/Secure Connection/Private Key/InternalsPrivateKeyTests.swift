/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

class InternalsPrivateKeyTests: XCTestCase {

    func testPrivate_whenPEM_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(Array(data), format: .pem).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .pem))
    }

    func testPrivate_whenDER_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()

        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(Array(data), format: .der).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .der))
    }

    func testPrivate_whenPEMWithPassword_shouldBeValid() async throws {
        // Given
        let password = "password123"
        let certificates = Certificates().client(password: true)

        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(Array(data), format: .pem) {
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
        let certificates = Certificates(.der).client(password: true)

        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(Array(data), format: .der) {
            $0(Array(Data(password.utf8)))
        }.build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .der) {
            $0(Array(Data(password.utf8)))
        })
    }
}
