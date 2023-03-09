/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ClientCertificateTests: XCTestCase {

    #if os(macOS)
    func testLocalHost() async throws {
        // Given
        let password = "12345"
        let server = try OpenSSL("ca_host_server").certificate()
        let client = try OpenSSL("ca_host_client", with: [.pfx(password)]).certificate()
        let output = "Hello World"

        // When
        let openSSLServer = OpenSSLServer(output, certificate: server, clientAuthentication: client)
        try await openSSLServer.start {
            let onlineCertificate = try await DownloadCertificate("https://localhost:8080").download()
            try server.replace(onlineCertificate, for: \.certificateURL)

            let server = try server.write(into: .module)
            let client = try client.write(into: .module)

            let data = try await DataTask {
                BaseURL("localhost:8080")
                Path("index")

                ServerTrust(Certificate(
                    server.certificatePath,
                    in: .module
                ))

                if let pfxPath = client.personalFileExchangePath {
                    ClientCertificate(
                        name: pfxPath,
                        in: .module,
                        password: password
                    )
                }
            }
            .extractPayload()
            .result()

            // Then
            XCTAssertEqual(String(data: data, encoding: .utf8), output)
        }
    }
    #endif

    func testNeverBody() async throws {
        // Given
        let property = ClientCertificate(name: "any", in: .module, password: "")

        // Then
        try await assertNever(property.body)
    }
}
