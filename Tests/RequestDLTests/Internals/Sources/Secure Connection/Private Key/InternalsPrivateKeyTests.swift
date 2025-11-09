/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOSSL
@testable import RequestDL

struct InternalsPrivateKeyTests {

    @Test
    func private_whenPEM_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(Array(data), format: .pem).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(bytes: Array(data), format: .pem)
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenDER_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()

        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(Array(data), format: .der).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(bytes: Array(data), format: .der)
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenPEMWithPassword_shouldBeValid() async throws {
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
        let expectedPrivateKey = try NIOSSLPrivateKey(bytes: Array(data), format: .pem) {
            $0(password)
        }
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenDERWithPassword_shouldBeValid() async throws {
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
        let expectedPrivateKey = try NIOSSLPrivateKey(bytes: Array(data), format: .der) {
            $0(password)
        }
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenPEMFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(file, format: .pem).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(file: file, format: .pem)
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenDERFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()

        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(file, format: .der).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(file: file, format: .der)
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenPEMFileWithPassword_shouldBeValid() async throws {
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
        let expectedPrivateKey = try NIOSSLPrivateKey(file: file, format: .pem) {
            $0(password)
        }
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenDERFileWithPassword_shouldBeValid() async throws {
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
        let expectedPrivateKey = try NIOSSLPrivateKey(file: file, format: .der) {
            $0(password)
        }
        #expect(resolved == expectedPrivateKey)
    }
}
