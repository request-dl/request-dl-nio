//
//  BaseURLTests.swift
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
}
