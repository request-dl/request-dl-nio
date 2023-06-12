/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class BaseURLTests: XCTestCase {

    func testHttpURL() async throws {
        // Given
        let scheme = URLScheme.http
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testHttpsURL() async throws {
        // Given
        let scheme = URLScheme.https
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testFtpURL() async throws {
        // Given
        let scheme = URLScheme.ftp
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testSmtpURL() async throws {
        // Given
        let scheme = URLScheme.smtp
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testImapURL() async throws {
        // Given
        let scheme = URLScheme.imap
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testPopURL() async throws {
        // Given
        let scheme = URLScheme.pop
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testDnsURL() async throws {
        // Given
        let scheme = URLScheme.dns
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testSshURL() async throws {
        // Given
        let scheme = URLScheme.ssh
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testTelnetURL() async throws {
        // Given
        let scheme = URLScheme.telnet
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testDefaultURLWithoutProtocol() async throws {
        // Given
        let host = "google.com.br"

        // When
        let baseURL = BaseURL(host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "https://google.com.br")
    }

    func testCollisionBaseURL() async throws {
        // Given
        let host1 = "apple.com"
        let host2 = "google.com"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL(.ftp, host: host1)
            BaseURL(host2)
        })

        // Then
        XCTAssertEqual(resolved.request.url, "https://google.com")
    }

    func testNeverBody() async throws {
        // Given
        let property = BaseURL("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
