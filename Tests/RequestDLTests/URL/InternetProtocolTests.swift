/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class InternetProtocolTests: XCTestCase {

    func testHttpRawValue() {
        XCTAssertEqual(InternetProtocol.http, "http")
    }

    func testHttpsRawValue() {
        XCTAssertEqual(InternetProtocol.https, "https")
    }

    func testFtpRawValue() {
        XCTAssertEqual(InternetProtocol.ftp, "ftp")
    }

    func testSmtpRawValue() {
        XCTAssertEqual(InternetProtocol.smtp, "smtp")
    }

    func testImapRawValue() {
        XCTAssertEqual(InternetProtocol.imap, "imap")
    }

    func testPopRawValue() {
        XCTAssertEqual(InternetProtocol.pop, "pop")
    }

    func testDnsRawValue() {
        XCTAssertEqual(InternetProtocol.dns, "dns")
    }

    func testSshRawValue() {
        XCTAssertEqual(InternetProtocol.ssh, "ssh")
    }

    func testTelnetRawValue() {
        XCTAssertEqual(InternetProtocol.telnet, "telnet")
    }
}
