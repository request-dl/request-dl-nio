//
//  ClientCertificateTests.swift
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

final class ClientCertificateTests: XCTestCase {

    override class func tearDown() {
        super.tearDown()
        FatalError.restoreFatalError()
    }

    func testLocalHost() async throws {
        // Given
        let url = FileManager.default.temporaryDirectory.appending("SwiftServer.\(UUID())")

        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )

        let serverCertificateName = "test_local_server_ca"
        let clientCertificateName = "test_local_client_ca"
        let password = "12345"

        let process = try await MockServer.startWithCA(
            url: url,
            server: serverCertificateName,
            client: clientCertificateName,
            password: password
        )

        defer { process.interrupt() }

        try await MockServer.writeCertificatesIntoBundle(
            url: url,
            server: serverCertificateName,
            client: clientCertificateName
        )

        FatalError.replace { [weak process] in
            process?.interrupt()
            Swift.fatalError($0, file: $1, line: $2)
        }

        // When
        let data = try await DataTask {
            BaseURL("localhost:8080")
            Path("index.txt")

            ServerTrust(Certificate(
                serverCertificateName,
                in: .module
            ))

            ClientCertificate(
                name: clientCertificateName,
                in: .module,
                password: password
            )
        }
        .extractPayload()
        .response()

        // Then
        XCTAssertEqual(String(data: data, encoding: .utf8), "Hello World!\n")
    }

    func testNeverBody() async throws {
        // Given
        let type = ClientCertificate.self

        // Then
        XCTAssertTrue(type.Body.self == Never.self)
    }
}
