//
//  InternetProtocolTests.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

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
