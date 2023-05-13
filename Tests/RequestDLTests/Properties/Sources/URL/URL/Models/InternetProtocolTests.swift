/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class InternetProtocolTests: XCTestCase {

    func testHttpRawValue() async throws {
        XCTAssertEqual(InternetProtocol.http, "http")
    }

    func testHttpsRawValue() async throws {
        XCTAssertEqual(InternetProtocol.https, "https")
    }

    func testFtpRawValue() async throws {
        XCTAssertEqual(InternetProtocol.ftp, "ftp")
    }

    func testSmtpRawValue() async throws {
        XCTAssertEqual(InternetProtocol.smtp, "smtp")
    }

    func testImapRawValue() async throws {
        XCTAssertEqual(InternetProtocol.imap, "imap")
    }

    func testPopRawValue() async throws {
        XCTAssertEqual(InternetProtocol.pop, "pop")
    }

    func testDnsRawValue() async throws {
        XCTAssertEqual(InternetProtocol.dns, "dns")
    }

    func testSshRawValue() async throws {
        XCTAssertEqual(InternetProtocol.ssh, "ssh")
    }

    func testTelnetRawValue() async throws {
        XCTAssertEqual(InternetProtocol.telnet, "telnet")
    }

    func testProtocol_withStringLossless() async throws {
        // Given
        let internetProtocol = InternetProtocol.dns

        // When
        let string = String(internetProtocol)
        let losslessInternetProtocol = InternetProtocol(string)

        // Then
        XCTAssertEqual(string, internetProtocol.description)
        XCTAssertEqual(losslessInternetProtocol, internetProtocol)
    }
}
