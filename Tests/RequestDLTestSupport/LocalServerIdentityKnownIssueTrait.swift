//
// See LICENSE for this package's licensing information.
//

// Same guard as `NonFatalWatchdogTrait`: this target builds under every `swift build`, not
// just test runs, and `Testing` genuinely isn't there on some of those toolchains.
#if DEBUG && canImport(Testing)
import Testing

/// Downgrades the Keychain round-trip failure every ``LocalServer`` construction hits, under
/// `NIOTransport`-off, from a test failure to a known issue.
///
/// `PortableListener` (`LocalServer`'s Network.framework backend) presents a `SecIdentity` built
/// by `Internals.RawBytesIdentityBuilder.makeIdentity`, the same Keychain-backed path the
/// `.urlSession` client already uses for mTLS. That path needs a Keychain Sharing entitlement
/// this unsigned `swift test` binary doesn't have, on any platform — see
/// `RequestConfigurationURLSessionClientMTLSTests`'s own doc comment, which already tracks this
/// exact gap for the client side. Under the NIO backend this never came up: the NIO-based
/// `LocalServer` builds its own certificate straight from the PEM file via
/// `NIOSSLCertificate.fromPEMFile`, no Keychain involved. The portable backend has no such
/// shortcut — presenting a `SecIdentity` to `NWListener` is Keychain-backed on both the client
/// and the server side.
package struct LocalServerIdentityKnownIssueTrait: TestTrait, SuiteTrait, TestScoping {

    package var isRecursive: Bool { true }

    package func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // `isIntermittent: true`: most tests in a suite carrying this trait (via `isRecursive`)
        // never touch `LocalServer` at all, and even the ones that do only hit this Keychain gap
        // when the round trip genuinely fails. Without it, `withKnownIssue` itself fails every
        // test that *doesn't* hit the gap, for not reproducing a "known" issue that was never
        // expected to reproduce there in the first place.
        try await withKnownIssue(isIntermittent: true) {
            try await function()
        } matching: { issue in
            String(describing: issue.error).contains("OSStatus -25300")
        }
    }
}

extension Trait where Self == LocalServerIdentityKnownIssueTrait {

    /// Records the ``LocalServer`` Keychain round-trip's `OSStatus -25300` failure as a known
    /// issue instead of a test failure. Add to any suite that constructs a ``LocalServer``: under
    /// `NIOTransport`-on this never fires (nothing in that path touches the Keychain), so the
    /// trait is a no-op there.
    package static var knownLocalServerIdentityIssue: Self { Self() }
}
#endif
