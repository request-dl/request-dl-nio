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

/// Stress coverage for the race an audit flagged in `Internals.IdentityManager.release(label:)`:
/// Swift zeroes an `IdentityHandle`'s `weak var` as soon as its strong refcount hits zero,
/// independently of `IdentityManager`'s own lock -- before that handle's `deinit` (which calls
/// `release(label:)`) ever gets a chance to actually acquire it. A second caller building for the
/// same content-derived label can therefore win the lock first, see the already-zeroed weak
/// reference, and register a brand new handle before the original handle's `release(label:)` runs.
/// Before the fix, `release(label:)` deleted the label's Keychain items and cleared the registry
/// slot unconditionally, wiping out the fresh handle's items out from under it. The fix makes
/// `release(label:)` check `live[label]?.value == nil` (under the same lock) before doing either.
///
/// - Note: This exercises the exact call pattern the race needs (many concurrent build/release
/// cycles for one content-derived label), but does **not** reliably reproduce the bug on its own.
/// Confirmed by running it, unmodified, against the pre-fix code multiple times: it passed every
/// time. Two things make that expected rather than a sign the race isn't real: the window between
/// a handle's weak reference zeroing and its `release(label:)` actually acquiring the lock is
/// vanishingly small next to a `SecItemAdd`/`SecItemDelete` round trip, and even a hit is
/// self-healing here -- the very next `makeIdentity` call for the label just re-adds whatever a
/// stale `release` wrongly deleted, via the ordinary "not found, so add it" path, leaving no
/// externally visible symptom unless some other long-lived, non-rebuilding consumer needed those
/// exact Keychain items in that exact window. So treat this test as a general concurrency-safety
/// smoke test for `IdentityManager` under load (no crash, every build keeps succeeding), not as
/// proof the fix closes this specific race -- that argument is made in the doc comments on
/// `IdentityManager`/`release(label:)` themselves, from Swift's documented weak-reference
/// zeroing semantics, not from this test.
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

        // When: many tasks repeatedly build a handle, touch it, and let it go out of scope --
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
