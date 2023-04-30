/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

@RequestActor
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
        let password = NIOSSLSecureBytes("password123".utf8)
        let certificates = Certificates().client(password: true)

        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(
            Array(data),
            format: .pem,
            password: password
        ).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .pem) {
            $0(password)
        })
    }

    func testPrivate_whenDERWithPassword_shouldBeValid() async throws {
        // Given
        let password = NIOSSLSecureBytes("password123".utf8)
        let certificates = Certificates(.der).client(password: true)

        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(
            Array(data),
            format: .der,
            password: password
        ).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .der) {
            $0(password)
        })
    }

    func testPrivate_whenPEMFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(file, format: .pem).build()

        // Then
        XCTAssertEqual(resolved, try .init(file: file, format: .pem))
    }

    func testPrivate_whenDERFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()

        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(file, format: .der).build()

        // Then
        XCTAssertEqual(resolved, try .init(file: file, format: .der))
    }

    func testPrivate_whenPEMFileWithPassword_shouldBeValid() async throws {
        // Given
        let password = NIOSSLSecureBytes("password123".utf8)
        let certificates = Certificates().client(password: true)
        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(
            file,
            format: .pem,
            password: password
        ).build()

        // Then
        XCTAssertEqual(resolved, try .init(file: file, format: .pem) {
            $0(password)
        })
    }

    func testPrivate_whenDERFileWithPassword_shouldBeValid() async throws {
        // Given
        let password = NIOSSLSecureBytes("password123".utf8)
        let certificates = Certificates(.der).client(password: true)
        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(
            file,
            format: .der,
            password: password
        ).build()

        // Then
        XCTAssertEqual(resolved, try .init(file: file, format: .der) {
            $0(password)
        })
    }
}
