/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

#if os(macOS)
@available(macOS 12, *)
final class ModifiersConvertBytesToDataTests: XCTestCase {

    func testBytesToData() async throws {
        // Given
        let server = try OpenSSL("bytes_task_server_to_data", with: [.der]).certificate()
        let output = "Hello World"

        // When
        let openSSLServer = OpenSSLServer(output, certificate: server)
        try await openSSLServer.start {
            let server = try server.write(into: .module)

            let data = try await BytesTask {
                BaseURL("localhost:8080")
                Path("index")

                if let certificate = server.certificateDEREncodedPath {
                    ServerTrust(Certificate(
                        certificate,
                        in: .module
                    ))
                }
            }
            .extractPayload()
            .convertBytesToData()
            .result()

            // Then
            XCTAssertEqual(String(data: data, encoding: .utf8), output)
        }
    }

    func testBytesToDataBeforeExtractPayload() async throws {
        // Given
        let server = try OpenSSL("bytes_task_server_to_data", with: [.der]).certificate()
        let output = "Hello World"

        // When
        let openSSLServer = OpenSSLServer(output, certificate: server)
        try await openSSLServer.start {
            let server = try server.write(into: .module)

            let data = try await BytesTask {
                BaseURL("localhost:8080")
                Path("index")

                if let certificate = server.certificateDEREncodedPath {
                    ServerTrust(Certificate(
                        certificate,
                        in: .module
                    ))
                }
            }
            .convertBytesToData()
            .extractPayload()
            .result()

            // Then
            XCTAssertEqual(String(data: data, encoding: .utf8), output)
        }
    }
}
#endif
