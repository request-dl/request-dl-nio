//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Stress coverage for the race documented on `Internals.IdentityManager.release(label:)`: a
/// second caller can rebuild a handle for the same label while the original handle's own
/// `release(label:)` is still waiting on the lock, and `release(label:)` must not delete the
/// Keychain items the new handle just built. See that type's own doc comment for the ARC
/// mechanics.
///
/// - Note: This test exercises the call pattern the race needs, but does not reliably reproduce
/// it on its own — confirmed by running it against the unguarded code multiple times, where it
/// still passed every time. Two things explain that. First, the race window (between a handle's
/// weak reference zeroing and its `release(label:)` acquiring the lock) is vanishingly small next
/// to a `SecItemAdd`/`SecItemDelete` round trip. Second, a hit is self-healing: the very next
/// `makeIdentity` call for the label just re-adds whatever a stale release wrongly deleted, so
/// nothing looks wrong unless some other, non-rebuilding consumer needed those exact Keychain
/// items in that exact window. Treat this as a general concurrency-safety smoke test (no crash,
/// every build keeps succeeding under load), not as proof this specific race is closed.
struct InternalsIdentityManagerTests {

    @Test
    func makeIdentity_underConcurrentBuildAndReleaseChurnForTheSameLabel_keepsSucceeding() async throws {
        // Given: real certificate/key DER bytes, the same on every iteration below, so every
        // `makeIdentity` call resolves to IdentityManager's exact same content-derived label.
        let client = Certificates().client()
        let secureConnection = Internals.SecureConnection.testMTLSConnection(client: client)

        let certificateChain = try #require(secureConnection.certificateChain)
        let certificateDERs = try Internals.RawBytesIdentityBuilder.certificateDERs(from: certificateChain)
        let certificateDER = try #require(certificateDERs.first)

        let privateKeySource = try #require(secureConnection.privateKey)
        let privateKeyDER = try Internals.RawBytesIdentityBuilder.privateKeyDER(from: privateKeySource)

        // When: many tasks repeatedly build a handle, touch it, and let it go out of scope,
        // racing every other task's own build/release cycle for the identical label.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    for _ in 0..<25 {
                        let handle = try Internals.RawBytesIdentityBuilder.makeIdentity(
                            certificateDER: certificateDER,
                            privateKeyDER: privateKeyDER
                        )
                        _ = handle.identity
                    }
                }
            }

            try await group.waitForAll()
        }

        // Then: the Keychain items must still be there for a fresh build to find.
        let finalHandle = try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: certificateDER,
            privateKeyDER: privateKeyDER
        )
        _ = finalHandle.identity
    }
}

extension Internals.SecureConnection {

    fileprivate static func testMTLSConnection(client: CertificateResource) -> Self {
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(client.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.privateKey = .privateKey(
            .init(client.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
        )
        return secureConnection
    }
}

#endif
