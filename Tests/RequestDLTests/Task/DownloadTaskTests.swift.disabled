/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

#if os(macOS)
final class DownloadTaskTests: XCTestCase {

    func testDownloadTask() async throws {
        // Given
        let server = try OpenSSL("data_task_server", with: [.der]).certificate()
        let output = "Hello World"

        // When
        let openSSLServer = OpenSSLServer(output, certificate: server)
        try await openSSLServer.start {
            let server = try server.write(into: .module)

            let url = try await DownloadTask {
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

            let data = String(data: try Data(contentsOf: url), encoding: .utf8)

            // Then
            XCTAssertEqual(data, output)
        }
    }
}
#endif
