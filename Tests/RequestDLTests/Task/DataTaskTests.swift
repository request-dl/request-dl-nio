/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class DataTaskTests: XCTestCase {

    func testDataTask() async throws {
        // Given
        let server = try OpenSSL("data_task_server").certificate()
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
}
