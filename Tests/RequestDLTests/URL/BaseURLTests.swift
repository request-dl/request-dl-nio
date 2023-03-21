/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class BaseURLTests: XCTestCase {

    func testHttpURL() async throws {
        // Given
        let internetProtocol = InternetProtocol.http
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "\(internetProtocol)://\(host)")
    }

    func testHttpsURL() async throws {
        // Given
        let internetProtocol = InternetProtocol.https
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "\(internetProtocol)://\(host)")
    }

    func testFtpURL() async throws {
        // Given
        let internetProtocol = InternetProtocol.ftp
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "\(internetProtocol)://\(host)")
    }

    func testSmtpURL() async throws {
        // Given
        let internetProtocol = InternetProtocol.smtp
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "\(internetProtocol)://\(host)")
    }

    func testImapURL() async throws {
        // Given
        let internetProtocol = InternetProtocol.imap
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "\(internetProtocol)://\(host)")
    }

    func testPopURL() async throws {
        // Given
        let internetProtocol = InternetProtocol.pop
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "\(internetProtocol)://\(host)")
    }

    func testDnsURL() async throws {
        // Given
        let internetProtocol = InternetProtocol.dns
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "\(internetProtocol)://\(host)")
    }

    func testSshURL() async throws {
        // Given
        let internetProtocol = InternetProtocol.ssh
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "\(internetProtocol)://\(host)")
    }

    func testTelnetURL() async throws {
        // Given
        let internetProtocol = InternetProtocol.telnet
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "\(internetProtocol)://\(host)")
    }

    func testDefaultURLWithoutProtocol() async throws {
        // Given
        let host = "google.com.br"

        // When
        let baseURL = BaseURL(host)
        let (_, request) = try await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url, "https://google.com.br")
    }

    func testCollisionBaseURL() async throws {
        // Given
        let host1 = "apple.com"
        let host2 = "google.com"

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL(.ftp, host: host1)
            BaseURL(host2)
        })

        // Then
        XCTAssertEqual(request.url, "ftp://apple.com")
    }

    func testNeverBody() async throws {
        // Given
        let property = BaseURL("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
