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
        let resolved = try await resolve(TestProperty {
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

        let sut = try resolved.session.configuration.secureConnection?.pskIdentityResolver?(hint)

        // Then
        XCTAssertEqual(sut?.key, key)
        XCTAssertEqual(sut?.identity, identity)
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

    fileprivate final class ClientResolver: SSLPSKIdentityResolver {

        let key: NIOSSLSecureBytes
        let identity: String

        let received: @Sendable (String) -> Void

        init(
            key: NIOSSLSecureBytes,
            identity: String,
            received: @escaping @Sendable (String) -> Void
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
}
