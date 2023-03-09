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
        let server = try OpenSSL("ca_host_server", with: [.der]).certificate()
        let client = try OpenSSL("ca_host_client", with: [.pkcs12(password)]).certificate()

        let output = "Hello World"

        // When
        let openSSLServer = OpenSSLServer(output, certificate: server, clientAuthentication: client)
        try await openSSLServer.start {
            let server = try server.write(into: .module)
            let client = try client.write(into: .module)

            let data = try await DataTask {
                BaseURL("localhost:8080")
                Path("index")

                if let server = server.certificateDEREncodedPath {
                    ServerTrust(Certificate(
                        server,
                        in: .module
                    ))
                }

                if let pkcs12Path = client.pkcs12Path {
                    ClientCertificate(
                        name: pkcs12Path,
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
