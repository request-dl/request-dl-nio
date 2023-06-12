/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class URLSchemeTests: XCTestCase {

    func testHttpRawValue() async throws {
        XCTAssertEqual(URLScheme.http, "http")
    }

    func testHttpsRawValue() async throws {
        XCTAssertEqual(URLScheme.https, "https")
    }

    func testFtpRawValue() async throws {
        XCTAssertEqual(URLScheme.ftp, "ftp")
    }

    func testSmtpRawValue() async throws {
        XCTAssertEqual(URLScheme.smtp, "smtp")
    }

    func testImapRawValue() async throws {
        XCTAssertEqual(URLScheme.imap, "imap")
    }

    func testPopRawValue() async throws {
        XCTAssertEqual(URLScheme.pop, "pop")
    }

    func testDnsRawValue() async throws {
        XCTAssertEqual(URLScheme.dns, "dns")
    }

    func testSshRawValue() async throws {
        XCTAssertEqual(URLScheme.ssh, "ssh")
    }

    func testTelnetRawValue() async throws {
        XCTAssertEqual(URLScheme.telnet, "telnet")
    }

    func testProtocol_withStringLossless() async throws {
        // Given
        let scheme = URLScheme.dns

        // When
        let string = String(scheme)
        let losslessScheme = URLScheme(string)

        // Then
        XCTAssertEqual(string, scheme.description)
        XCTAssertEqual(losslessScheme, scheme)
    }
}
