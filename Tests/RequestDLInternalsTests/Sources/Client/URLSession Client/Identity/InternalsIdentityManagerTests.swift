//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Dispatch
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
            let manager = Internals.IdentityManager { label, _, useDataProtectionKeychain in
                deletions.withLockedValue {
                    $0.append(Deletion(label: label, useDataProtectionKeychain: useDataProtectionKeychain))
                }
            }

            // When
            var handle: Internals.IdentityHandle? = try manager.handle(for: "test.label") {
                (source.identity, useDataProtectionKeychain, nil)
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

    /// The Keychain keeps one item per key however many certificates it is paired with. The key
    /// goes with the last identity built from it, not with the one that added it, or the others
    /// would be left without it.
    @Test
    func release_whenIdentitiesShareAKey_deletesTheKeyWithTheLastOne() async throws {
        func run() throws {
            // Given
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

            let deletions = LockedValueBox<[String]>([])
            let manager = Internals.IdentityManager { label, _, _ in
                deletions.withLockedValue { $0.append(label) }
            }

            var first: Internals.IdentityHandle? = try manager.handle(for: "cert.first", keyLabel: "key") {
                (source.identity, false, nil)
            }
            var second: Internals.IdentityHandle? = try manager.handle(for: "cert.second", keyLabel: "key") {
                (source.identity, false, nil)
            }

            // When / Then
            first = nil
            #expect(deletions.withLockedValue { $0 } == ["cert.first"])

            second = nil
            #expect(deletions.withLockedValue { $0 } == ["cert.first", "cert.second", "key"])

            _ = (first, second)
        }

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

extension InternalsIdentityManagerTests {

    /// The legacy macOS keychain does not keep a certificate's label, so the certificate the
    /// handle's build added is deleted by reference. A handle whose build found it already stored
    /// has none to give, and must not delete one that someone else stored.
    @Test
    func release_whenTheHandleOwnsItsCertificate_deletesItByReferenceAndNotTheKey() async throws {
        func run() throws {
            // Given
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
            let certificate = try Internals.RawBytesIdentityBuilder.certificate(fromDER: certificateDER)

            let deletions = LockedValueBox<[String]>([])
            let manager = Internals.IdentityManager { label, certificate, _ in
                deletions.withLockedValue { $0.append("\(label):\(certificate == nil ? "label" : "reference")") }
            }

            var owning: Internals.IdentityHandle? = try manager.handle(for: "cert.owned", keyLabel: "key") {
                (source.identity, false, certificate)
            }
            var notOwning: Internals.IdentityHandle? = try manager.handle(for: "cert.found", keyLabel: "key") {
                (source.identity, false, nil)
            }

            // When / Then
            owning = nil
            notOwning = nil

            #expect(deletions.withLockedValue { $0 } == ["cert.owned:reference", "cert.found:label", "key:label"])

            _ = (owning, notOwning)
        }

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

extension InternalsIdentityManagerTests {

    /// A new handle can be registered for a label while the old one is already dying (its weak
    /// reference is zeroed before its `deinit` takes the lock). The new one found the old one's
    /// certificate "already there" and does not own it, so the old one's release hands it over,
    /// or nobody would ever delete it.
    @Test
    func release_whenANewerHandleIsAlreadyRegisteredForTheLabel_handsItTheCertificate() async throws {
        func run() throws {
            // Given
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
            let certificate = try Internals.RawBytesIdentityBuilder.certificate(fromDER: certificateDER)

            let deletions = LockedValueBox<[String]>([])
            let manager = Internals.IdentityManager { label, certificate, _ in
                deletions.withLockedValue { $0.append("\(label):\(certificate == nil ? "label" : "reference")") }
            }

            var newer: Internals.IdentityHandle? = try manager.handle(for: "cert") {
                (source.identity, false, nil)
            }

            // When: the older handle's release runs while the newer one is registered.
            manager.release(
                label: "cert",
                keyLabel: "cert",
                ownedCertificate: certificate,
                useDataProtectionKeychain: false
            )

            #expect(deletions.withLockedValue { $0 }.isEmpty)

            // Then: the newer one deletes it with its own release.
            newer = nil

            #expect(deletions.withLockedValue { $0 } == ["cert:reference"])

            _ = newer
        }

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

#if os(macOS)

extension InternalsIdentityManagerTests {

    /// `release(...)` looks at the handle registered for its label while holding the lock. That
    /// look takes a strong reference, and if another thread drops the last outside reference to
    /// that handle meanwhile, the look is the last one: the handle is deallocated there, under the
    /// lock, its `deinit` calls `release(...)`, and the non-reentrant lock aborts the process
    /// (`_os_unfair_lock_recursive_abort`). A handle must only ever be deallocated outside it.
    ///
    /// Several threads keep calling `release` for the label, so that one of them is almost always
    /// inside the lock looking at the registered handle, while this thread drops the handle again
    /// and again. Before the fix, sooner or later a drop lands in a look and kills the process.
    @Test
    func release_whenTheHandleRegisteredForTheLabelIsDroppedMeanwhile_neverDeallocatesItUnderTheLock() throws {
        // Given
        let fixture = try InternalsRawBytesIdentityBuilderKeychainTests.Fixture()
        defer { fixture.cleanUp() }

        let source = try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: fixture.certificateDER,
            privateKeyDER: fixture.pkcs1
        )

        let manager = Internals.IdentityManager { _, _, _ in }
        let isRunning = LockedValueBox(true)
        let releasers = DispatchGroup()

        for _ in 0..<4 {
            DispatchQueue.global().async(group: releasers) {
                while isRunning.withLockedValue({ $0 }) {
                    manager.release(
                        label: "race",
                        keyLabel: "race",
                        ownedCertificate: nil,
                        useDataProtectionKeychain: false
                    )
                }
            }
        }

        // When
        var failure: (any Error)?
        for _ in 0..<5_000 {
            do {
                var registered: Internals.IdentityHandle? = try manager.handle(for: "race") {
                    (source.identity, false, nil)
                }
                registered = nil
                _ = registered
            } catch {
                failure = error
                break
            }
        }

        isRunning.withLockedValue { $0 = false }
        releasers.wait()

        // Then: still here.
        #expect(failure == nil)
    }
}

#endif

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
