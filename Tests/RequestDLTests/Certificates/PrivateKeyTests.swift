/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class PrivateKeyTests: XCTestCase {

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

                SecureConnection {
                    Trusts(server.certificatePath, in: .module)

                    if let pkcs12Path = client.pkcs12Path {
                        PrivateKey(pkcs12Path, in: .module) {
                            $0(password.utf8)
                        }
                    }
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
        let property = PrivateKey("any", in: .module) {
            $0("".utf8)
        }

        // Then
        try await assertNever(property.body)
    }
}
