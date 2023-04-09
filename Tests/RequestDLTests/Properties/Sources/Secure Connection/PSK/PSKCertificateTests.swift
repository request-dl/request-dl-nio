/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

class PSKCertificateTests: XCTestCase {

    func testCertificate_whenInitClient_shouldBeValid() async throws {
        // Given
        let hint = "hint"
        let identity = "host"
        let key = NIOSSLSecureBytes([0, 1, 2])
        var receivedHint: String?

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.PSKCertificate(.client) { description in
                    receivedHint = description.serverHint
                    return .init(
                        key: key,
                        identity: identity
                    )
                }
            }
        })

        let sut = try session.configuration.secureConnection?.pskClientCallback?(hint)

        // Then
        XCTAssertEqual(receivedHint, hint)
        XCTAssertEqual(sut?.key, key)
        XCTAssertEqual(sut?.identity, identity)
    }

    func testCertificate_whenInitServer_shouldBeValid() async throws {
        // Given
        let serverHint = "s.hint"
        let clientHint = "c.hint"
        let key = NIOSSLSecureBytes([0, 1, 2])

        var receivedServerHint: String?
        var receivedClientHint: String?

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.PSKCertificate(.server) { description in
                    receivedServerHint = description.serverHint
                    receivedClientHint = description.clientHint
                    return .init(key)
                }
            }
        })

        let sut = try session.configuration.secureConnection?.pskServerCallback?(serverHint, clientHint)

        // Then
        XCTAssertEqual(receivedServerHint, serverHint)
        XCTAssertEqual(receivedClientHint, clientHint)
        XCTAssertEqual(sut?.key, key)
    }

    func testCertificate_whenSetPSKHint_shouldContainsInSecureConnection() async throws {
        // Given
        let hint = "some.hint"

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.PSKCertificate(.client) { description in
                    PSKClientCertificate(
                        key: .init([0, 1, 2]),
                        identity: description.serverHint
                    )
                }
                .hint(hint)
            }
        })

        let sut = session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.pskHint, hint)
    }

    func testPSK_whenAccessBody_shouldBeNever() async throws {
        // Given
        let sut = RequestDL.PSKCertificate { _ in
            .init(key: .init([0, 1, 2]), identity: "")
        }

        // Then
        try await assertNever(sut.body)
    }
}
