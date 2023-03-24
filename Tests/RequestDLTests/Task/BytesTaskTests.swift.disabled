/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

#if os(macOS)
@available(macOS 12, *)
final class BytesTaskTests: XCTestCase {

    func testBytesTask() async throws {
        // Given
        let server = try OpenSSL("bytes_task_server", with: [.der]).certificate()
        let output = "Hello World"
        var data = Data()

        // When
        let openSSLServer = OpenSSLServer(output, certificate: server)
        try await openSSLServer.start {
            let server = try server.write(into: .module)

            let bytes = try await BytesTask {
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
            .result()

            for try await byte in bytes {
                data.append(byte)
            }

            // Then
            XCTAssertEqual(String(data: data, encoding: .utf8), output)
        }
    }
}
#endif
