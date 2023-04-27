/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

class PSKIdentityTests: XCTestCase {

    func testIdentity_whenClientResolver() async throws {
        // Given
        let hint = "hint"
        let identity = "host"
        let key = NIOSSLSecureBytes([0, 1, 2])

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.PSKIdentity(
                    ClientResolver(
                        key: key,
                        identity: identity,
                        received: {
                            XCTAssertEqual($0, hint)
                        }
                    )
                )
            }
        })

        let sut = try session.configuration.secureConnection?.pskClientIdentityResolver?(hint)

        // Then
        XCTAssertEqual(sut?.key, key)
        XCTAssertEqual(sut?.identity, identity)
    }

    func testIdentity_whenServerResolver() async throws {
        // Given
        let serverHint = "s.hint"
        let clientIdentity = "c.identity"
        let key = NIOSSLSecureBytes([0, 1, 2])

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.PSKIdentity(
                    ServerResolver(key) {
                        XCTAssertEqual($0, serverHint)
                        XCTAssertEqual($1, clientIdentity)
                    }
                )
            }
        })

        let sut = try session.configuration.secureConnection?.pskServerIdentityResolver?(serverHint, client: clientIdentity)

        // Then
        XCTAssertEqual(sut?.key, key)
    }

    func testPSK_whenAccessBody_shouldBeNever() async throws {
        // Given
        let identity = "host"
        let key = NIOSSLSecureBytes([0, 1, 2])

        // When
        let sut = RequestDL.PSKIdentity(
            ClientResolver(
                key: key,
                identity: identity,
                received: { _ in }
            )
        )

        // Then
        try await assertNever(sut.body)
    }
}

extension PSKIdentityTests {

    fileprivate final class ClientResolver: SSLPSKClientIdentityResolver {

        let key: NIOSSLSecureBytes
        let identity: String

        let received: @Sendable (String) -> Void

        init(
            key: NIOSSLSecureBytes,
            identity: String,
            received: @Sendable @escaping (String) -> Void
        ) {
            self.key = key
            self.identity = identity
            self.received = received
        }

        func callAsFunction(_ hint: String) throws -> PSKClientIdentityResponse {
            received(hint)
            return .init(
                key: key,
                identity: identity
            )
        }
    }

    fileprivate final class ServerResolver: SSLPSKServerIdentityResolver {

        let key: NIOSSLSecureBytes
        let received: @Sendable (String, String) -> Void

        init(
            _ key: NIOSSLSecureBytes,
            received: @Sendable @escaping (String, String) -> Void
        ) {
            self.key = key
            self.received = received
        }

        func callAsFunction(_ hint: String, client identity: String) throws -> PSKServerIdentityResponse {
            received(hint, identity)
            return .init(key: key)
        }
    }
}

@available(*, deprecated)
extension PSKIdentityTests {

    func testCertificate_whenInitClient_shouldBeValid() async throws {
        // Given
        let hint = "hint"
        let identity = "host"
        let key = NIOSSLSecureBytes([0, 1, 2])

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.PSKIdentity(.client) { description in

                    XCTAssertEqual(description.serverHint, hint)

                    return .init(
                        key: key,
                        identity: identity
                    )
                }
            }
        })

        let sut = try session.configuration.secureConnection?.pskClientIdentityResolver?(hint)

        // Then

        XCTAssertEqual(sut?.key, key)
        XCTAssertEqual(sut?.identity, identity)
    }

    func testCertificate_whenInitServer_shouldBeValid() async throws {
        // Given
        let serverHint = "s.hint"
        let clientIdentity = "c.identity"
        let key = NIOSSLSecureBytes([0, 1, 2])

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.PSKIdentity(.server) { description in

                    XCTAssertEqual(description.serverHint, serverHint)
                    XCTAssertEqual(description.clientHint, clientIdentity)

                    return .init(key)
                }
            }
        })

        let sut = try session.configuration.secureConnection?.pskServerIdentityResolver?(serverHint, client: clientIdentity)

        // Then
        XCTAssertEqual(sut?.key, key)
    }

    func testCertificate_whenSetPSKHint_shouldContainsInSecureConnection() async throws {
        // Given
        let hint = "some.hint"

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.PSKIdentity(.client) { description in
                    PSKClientIdentity(
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
}
