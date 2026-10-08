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
/// it on its own: it still passed every time against the unguarded code. Two things explain
/// that. First, the race window (between a handle's weak reference zeroing and its
/// `release(label:)` acquiring the lock) is vanishingly small next to a
/// `SecItemAdd`/`SecItemDelete` round trip. Second, a hit is self-healing: the very next
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
        func run() async throws {
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

        #if os(macOS) || !canImport(Darwin)
        try await run()
        #else
        await withKnownIssue(
            "no Keychain Sharing entitlement on this platform's SwiftPM-generated Xcode scheme; see RequestConfigurationURLSessionClientMTLSTests's own doc comment"
        ) {
            try await run()
        }
        #endif
    }
}

extension InternalsIdentityManagerTests {

    private struct Deletion: Equatable, Sendable {
        let label: String
        let useDataProtectionKeychain: Bool
    }

    /// On macOS the build stores in the data-protection Keychain when the process may use it, so
    /// the release must delete from the Keychain the handle was built in, or the imported
    /// private key stays behind.
    @Test(arguments: [true, false])
    func release_whenLastHandleGoesAway_deletesFromTheKeychainItWasBuiltIn(
        _ useDataProtectionKeychain: Bool
    ) async throws {
        func run() throws {
            // Given: a real identity (what `SecIdentity` is only ever made of), wrapped by a manager
            // that records deletions instead of touching the Keychain.
            let client = Certificates().client()
            let secureConnection = Internals.SecureConnection.testMTLSConnection(client: client)

            let certificateChain = try #require(secureConnection.certificateChain)
            let certificateDER = try #require(
                try Internals.RawBytesIdentityBuilder.certificateDERs(from: certificateChain).first
            )
            let privateKeySource = try #require(secureConnection.privateKey)
            let privateKeyDER = try Internals.RawBytesIdentityBuilder.privateKeyDER(from: privateKeySource)

            let source = try Internals.RawBytesIdentityBuilder.makeIdentity(
                certificateDER: certificateDER,
                privateKeyDER: privateKeyDER
            )

            let deletions = LockedValueBox<[Deletion]>([])
            let manager = Internals.IdentityManager { label, useDataProtectionKeychain in
                deletions.withLockedValue {
                    $0.append(Deletion(label: label, useDataProtectionKeychain: useDataProtectionKeychain))
                }
            }

            // When
            var handle: Internals.IdentityHandle? = try manager.handle(for: "test.label") {
                (source.identity, useDataProtectionKeychain)
            }

            // Then: nothing is deleted while the handle is alive.
            #expect(handle != nil)
            #expect(deletions.withLockedValue { $0 }.isEmpty)

            handle = nil

            #expect(
                deletions.withLockedValue { $0 }
                    == [Deletion(label: "test.label", useDataProtectionKeychain: useDataProtectionKeychain)]
            )
        }

        // Building the identity writes the Keychain, which only macOS allows without the Keychain
        // Sharing capability the SwiftPM-generated Xcode scheme of the other platforms lacks.
        #if os(macOS)
        try run()
        #else
        await withKnownIssue(
            "no Keychain Sharing entitlement on this platform's SwiftPM-generated Xcode scheme; see RequestConfigurationURLSessionClientMTLSTests's own doc comment"
        ) {
            try run()
        }
        #endif
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
