/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ServerTrustTests: XCTestCase {

    #if os(macOS)
    func testValidServer() async throws {
        // Given
        let server = try OpenSSL("trust_valid_server").certificate()
        let output = "Hello World"

        // When
        let openSSLServer = OpenSSLServer(output, certificate: server)
        try await openSSLServer.start {
            let onlineCertificate = try await DownloadCertificate("https://localhost:8080").download()
            try server.replace(onlineCertificate, for: \.certificateURL)

            let server = try server.write(into: .module)

            let data = try await DataTask {
                BaseURL("localhost:8080")
                Path("index")

                ServerTrust(Certificate(
                    server.certificatePath,
                    in: .module
                ))
            }
            .extractPayload()
            .result()

            // Then
            XCTAssertEqual(String(data: data, encoding: .utf8), output)
        }
    }
    #endif

    #if os(macOS)
    func testInvalidServer() async throws {
        // Given
        let server = try OpenSSL("trust_invalid_server").certificate()
        let invalid = try OpenSSL("trust_invalid_server.2").certificate()
        let output = "Hello World"

        // When
        let openSSLServer = OpenSSLServer(output, certificate: server)
        var urlError: URLError?

        do {
            try await openSSLServer.start {
                let server = try invalid.write(into: .module)

                let data = try await DataTask {
                    BaseURL("localhost:8080")
                    Path("index")

                    ServerTrust(Certificate(
                        server.certificatePath,
                        in: .module
                    ))
                }
                .extractPayload()
                .result()

                // Then
                XCTAssertEqual(String(data: data, encoding: .utf8), output)
            }
        } catch let error as URLError {
            urlError = error
        } catch {
            throw error
        }

        // Then
        XCTAssertNotNil(urlError)
        XCTAssertEqual(urlError?.code.rawValue, -999)
    }
    #endif

    func testNeverBody() async throws {
        // Given
        let property = ServerTrust(Certificate("any", in: .module))

        // Then
        try await assertNever(property.body)
    }
}
