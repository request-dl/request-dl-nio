//
//  ServerTrustTests.swift
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

final class ServerTrustTests: XCTestCase {

    func testValidServer() async throws {
        // Given
        let certificate = try await DownloadCertificate(from: "https://github.com").download()
        let url = Bundle.module.normalizedResourceURL
            .appending("github_certificate", extension: "cer")

        try certificate.write(to: url)

        let property = ServerTrust(Certificate("github_certificate", in: .module))

        // When
        let response = try await DataTask {
            BaseURL("github.com")
            property
        }.response().response as? HTTPURLResponse

        // Then
        XCTAssertEqual(response?.statusCode, 200)
    }

    func testInvalidServer() async throws {
        // Given
        let certificate = try await DownloadCertificate(from: "https://apple.com").download()
        let url = Bundle.module.normalizedResourceURL
            .appending("apple_certificate", extension: "cer")

        try certificate.write(to: url)

        let property = ServerTrust(Certificate("apple_certificate", in: .module))

        // When
        var responseError: URLError?

        do {
            _ = try await DataTask {
                BaseURL("github.com")
                property
            }.response()
        } catch {
            responseError = error as? URLError
        }

        // Then
        XCTAssertNotNil(responseError)
        XCTAssertEqual(responseError?.code.rawValue, -999)
    }

    func testNeverBody() async throws {
        // Given
        let type = ServerTrust.self

        // Then
        XCTAssertTrue(type.Body.self == Never.self)
    }
}
