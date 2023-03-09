/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class BaseURLTests: XCTestCase {

    func testHttpURL() async {
        // Given
        let internetProtocol = InternetProtocol.http
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "\(internetProtocol)://\(host)")
    }

    func testHttpsURL() async {
        // Given
        let internetProtocol = InternetProtocol.https
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "\(internetProtocol)://\(host)")
    }

    func testFtpURL() async {
        // Given
        let internetProtocol = InternetProtocol.ftp
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "\(internetProtocol)://\(host)")
    }

    func testSmtpURL() async {
        // Given
        let internetProtocol = InternetProtocol.smtp
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "\(internetProtocol)://\(host)")
    }

    func testImapURL() async {
        // Given
        let internetProtocol = InternetProtocol.imap
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "\(internetProtocol)://\(host)")
    }

    func testPopURL() async {
        // Given
        let internetProtocol = InternetProtocol.pop
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "\(internetProtocol)://\(host)")
    }

    func testDnsURL() async {
        // Given
        let internetProtocol = InternetProtocol.dns
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "\(internetProtocol)://\(host)")
    }

    func testSshURL() async {
        // Given
        let internetProtocol = InternetProtocol.ssh
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "\(internetProtocol)://\(host)")
    }

    func testTelnetURL() async {
        // Given
        let internetProtocol = InternetProtocol.telnet
        let host = "google.com"

        // When
        let baseURL = BaseURL(internetProtocol, host: host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "\(internetProtocol)://\(host)")
    }

    func testDefaultURLWithoutProtocol() async {
        // Given
        let host = "google.com.br"

        // When
        let baseURL = BaseURL(host)
        let (_, request) = await resolve(baseURL)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://google.com.br")
    }

    func testCollisionBaseURL() async {
        // Given
        let host1 = "apple.com"
        let host2 = "google.com"

        // When
        let (_, request) = await resolve(TestProperty {
            BaseURL(.ftp, host: host1)
            BaseURL(host2)
        })

        // Then
        XCTAssertEqual(request.url?.absoluteString, "ftp://apple.com")
    }

    func testNeverBody() async throws {
        // Given
        let property = BaseURL("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
