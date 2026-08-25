//
// See LICENSE for this package's licensing information.
//

import NIOHTTP1
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsSessionConfigurationExecutorTests {

    @Test
    func configuration_whenNothingSet_urlSessionIncompatibilityReasonsIsEmpty() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().isEmpty)
    }

    @Test
    func configuration_whenDNSOverrideSet_containsReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // When
        configuration.dnsOverride = ["example.com": "127.0.0.1"]

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.dnsOverrideUnderURLSession))
    }

    @Test
    func configuration_whenHTTP1OnlySet_containsReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // When
        configuration.httpVersion = .http1Only

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.http1OnlyUnderURLSession))
    }

    @Test
    func configuration_whenAutomaticHTTPVersionSet_doesNotContainReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // When
        configuration.httpVersion = .automatic

        // Then
        #expect(!configuration.urlSessionIncompatibilityReasons().contains(.http1OnlyUnderURLSession))
    }

    @Test
    func configuration_whenProxyConnectHeadersSet_containsReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        var connectHeaders = HTTPHeaders()
        connectHeaders.add(name: "X-Proxy-Token", value: "abc123")

        // When
        configuration.proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: nil,
            connectHeaders: connectHeaders
        )

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.proxyConnectHeadersUnderURLSession))
    }

    @Test
    func configuration_whenHTTPProxyWithoutConnectHeaders_doesNotContainReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // When
        configuration.proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: nil
        )

        // Then
        let reasons = configuration.urlSessionIncompatibilityReasons()
        #expect(!reasons.contains(.proxyConnectHeadersUnderURLSession))
        #expect(!reasons.contains(.proxySOCKSUnderURLSession))
    }

    @Test
    func configuration_whenSOCKSProxySet_containsReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // When
        configuration.proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .socks,
            authorization: nil
        )

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.proxySOCKSUnderURLSession))
    }

    @Test
    func configuration_whenProxyBearerAuthorizationSet_containsReason() async throws {
        // Given -- no `URLCredential` shape can carry an arbitrary bearer token, unlike
        // `.basic`/`.basicRawCredentials`, which map onto the proxy authentication challenge
        // delegate cleanly.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // When
        configuration.proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: .bearer(tokens: "abc123")
        )

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.proxyBearerAuthorizationUnderURLSession))
    }

    @Test
    func configuration_whenProxyBasicAuthorizationSet_doesNotContainReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // When
        configuration.proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: .basic(username: "user", password: "pass")
        )

        // Then
        #expect(!configuration.urlSessionIncompatibilityReasons().contains(.proxyBearerAuthorizationUnderURLSession))
    }

    @Test
    func configuration_whenDecompressionDisabled_containsReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.decompression = .disabled

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.decompressionDisabledUnderURLSession))
    }

    @Test
    func configuration_whenDecompressionEnabled_doesNotContainReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.decompression = .enabled(.none)

        // Then
        #expect(!configuration.urlSessionIncompatibilityReasons().contains(.decompressionDisabledUnderURLSession))
    }

    @Test
    func configuration_whenSecureConnectionIncompatible_reasonsPropagate() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        var secureConnection = Internals.SecureConnection()
        secureConnection.pskHint = "hint"

        // When
        configuration.secureConnection = secureConnection

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.pskHint))
    }

    // MARK: - resolveExecutor()

    @Test
    func resolveExecutor_whenNothingSet_resolvesToURLSessionOnDarwin() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .urlSession)
        #else
        #expect(sut == .nio)
        #endif
    }

    @Test
    func resolveExecutor_whenIncompatibleWithURLSessionOnly_resolvesToNIOTransportServicesOnDarwin() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        // When -- fine under NIOTransportServices, unsupported under URLSession (bucket D)
        configuration.httpVersion = .http1Only

        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .nioTransportServices)
        #else
        #expect(sut == .nio)
        #endif
    }

    /// Executor compatibility is not a strict hierarchy: a field unsupported under URLSession and
    /// a *different* field unsupported under NIOTransportServices together must fall all the way
    /// back to `.nio`, not get silently paired with whichever executor happens to tolerate one
    /// of them.
    @Test
    func resolveExecutor_whenIncompatibleWithBothURLSessionAndNIOTransportServices_resolvesToNIO() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.httpVersion = .http1Only

        var secureConnection = Internals.SecureConnection()
        secureConnection.additionalTrustRoots = [.file("/dev/null")]
        configuration.secureConnection = secureConnection

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .nio)
    }

    @Test
    func resolveExecutor_whenAdditionalTrustRootsSet_resolvesToURLSessionOnDarwin() async throws {
        // Given -- reachable under URLSession, unlike under NIOTransportServices
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        var secureConnection = Internals.SecureConnection()
        secureConnection.additionalTrustRoots = [.file("/dev/null")]
        configuration.secureConnection = secureConnection

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .urlSession)
        #else
        #expect(sut == .nio)
        #endif
    }

    // MARK: - resolveExecutor() with preferredExecutor

    @Test
    func resolveExecutor_whenNIOTransportServicesPreferredAndCompatible_resolvesToItOverURLSession() async throws {
        // Given -- compatible with both `.urlSession` and `.nioTransportServices`, so the
        // preference is what breaks the tie rather than falling to the default priority order.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.preferredExecutor = .nioTransportServices

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .nioTransportServices)
        #else
        #expect(sut == .nio)
        #endif
    }

    @Test
    func resolveExecutor_whenNIOPreferred_resolvesToNIORegardlessOfOtherCompatibility() async throws {
        // Given -- compatible with everything, yet `.nio` is explicitly preferred.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.preferredExecutor = .nio

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .nio)
    }

    /// A preference the configuration can't actually satisfy is not an override. Resolution must
    /// fall through to whatever the default priority order would have picked among the
    /// compatible candidates, not honor the preference anyway.
    @Test
    func resolveExecutor_whenNIOTransportServicesPreferredButIncompatible_fallsBackToURLSession() async throws {
        // Given -- reachable under URLSession, unreachable under NIOTransportServices
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.preferredExecutor = .nioTransportServices

        var secureConnection = Internals.SecureConnection()
        secureConnection.additionalTrustRoots = [.file("/dev/null")]
        configuration.secureConnection = secureConnection

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .urlSession)
        #else
        #expect(sut == .nio)
        #endif
    }

    @Test
    func resolveExecutor_whenURLSessionPreferredButIncompatible_fallsBackToNIOTransportServices() async throws {
        // Given -- unreachable under URLSession (bucket D), unaffected under NIOTransportServices
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.preferredExecutor = .urlSession
        configuration.httpVersion = .http1Only

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .nioTransportServices)
        #else
        #expect(sut == .nio)
        #endif
    }

    // MARK: - resolveExecutor() with enableNetworkFramework

    /// `enableNetworkFramework(true)` (`Session.enableNetworkFramework(_:)`) is already public,
    /// released API that predates `preferredExecutor` -- its whole point, historically, was
    /// opting a session into NIOTransportServices. Since this method's own
    /// NIOTransportServices-vs-plain-NIO answer drives a real request, `.urlSession`'s default
    /// first-priority position would otherwise silently take over for a caller who only ever set
    /// this flag, changing which transport they get without them touching a single line of their
    /// own code. This section is the regression coverage for treating the flag as an implicit
    /// `preferredExecutor(.nioTransportServices)` specifically to prevent that.
    @Test
    func resolveExecutor_whenNetworkFrameworkEnabledWithoutExplicitPreference_resolvesToNIOTransportServices()
        async throws
    {
        // Given -- compatible with `.urlSession` too, so the implicit preference is what breaks
        // the tie rather than `.urlSession`'s own default priority.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.enableNetworkFramework = true

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .nioTransportServices)
        #else
        #expect(sut == .nio)
        #endif
    }

    @Test
    func resolveExecutor_whenNetworkFrameworkEnabledAndURLSessionExplicitlyPreferred_explicitPreferenceWins()
        async throws
    {
        // Given -- an explicit `preferredExecutor` (any case) always outranks the implicit one
        // `enableNetworkFramework` contributes.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.enableNetworkFramework = true
        configuration.preferredExecutor = .urlSession

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .urlSession)
        #else
        #expect(sut == .nio)
        #endif
    }

    /// The flag's implicit preference is still just a preference, not a guarantee -- a
    /// NIOTransportServices-incompatible field must still fall through past it, the same way an
    /// explicit `preferredExecutor(.nioTransportServices)` already does two tests above this
    /// section.
    @Test
    func resolveExecutor_whenNetworkFrameworkEnabledButIncompatible_fallsThroughToURLSession() async throws {
        // Given -- reachable under URLSession, unreachable under NIOTransportServices
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.enableNetworkFramework = true

        var secureConnection = Internals.SecureConnection()
        secureConnection.additionalTrustRoots = [.file("/dev/null")]
        configuration.secureConnection = secureConnection

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .urlSession)
        #else
        #expect(sut == .nio)
        #endif
    }

    // MARK: - resolveExecutor() with requiredExecutor

    /// Regression coverage for a real bug end-to-end testing caught -- `resolveExecutor()`'s own
    /// doc comment already claimed `requiredExecutor` "lets a caller override it," but the
    /// implementation below only ever consulted `preferredExecutor`. `requiredExecutor(.nio)`
    /// validated (via `requireExecutor(_:)`,
    /// called separately) without ever actually being the executor a real request dispatched
    /// over -- `resolveExecutor()` picked `.urlSession` anyway on a compatible config, silently.
    /// Caught by a `DataTaskTests` test pinning `.requiredExecutor(.nio)` to keep a client-cert
    /// mTLS test off `.urlSession`'s unconditional Keychain-Sharing gap, which kept hitting that
    /// gap anyway until this was fixed.
    @Test
    func resolveExecutor_whenNIORequired_resolvesToNIORegardlessOfPreferredExecutorOrCompatibility() async throws {
        // Given -- compatible with `.urlSession`, and even prefers it, yet `.nio` is required.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.preferredExecutor = .urlSession
        configuration.requiredExecutor = .nio

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .nio)
    }

    @Test
    func resolveExecutor_whenURLSessionRequired_resolvesToURLSessionRegardlessOfPreferredExecutor() async throws {
        // Given -- `requiredExecutor` is trusted unconditionally, on every platform (see the
        // "without prior validation" test below for why that's fine in practice even here).
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.preferredExecutor = .nio
        configuration.requiredExecutor = .urlSession

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .urlSession)
    }

    /// `resolveExecutor()` trusts `requiredExecutor` unconditionally and platform-independently
    /// by design (see its own doc comment, and the fact this returns before the
    /// `#if canImport(Darwin)` gate below) -- the compatibility check already happened, and
    /// already threw, in `requireExecutor(_:)`. This test documents that trust rather than
    /// re-deriving it: a config `requiredExecutor` claims is `.urlSession`-compatible despite
    /// `httpVersion == .http1Only` (a genuine bucket-D exclusion) still resolves to `.urlSession`
    /// here, on every platform, because nothing calls `requireExecutor(_:)` in this test to catch
    /// the mismatch first -- exactly mirroring what a caller who skips that call gets in
    /// production too. `Internals.ClientManager.resolvedClient(provider:sessionConfiguration:)`'s
    /// own non-Darwin branch is what actually keeps this harmless there in practice (it never
    /// looks at `resolveExecutor()`'s answer at all outside Darwin), not this method.
    @Test
    func resolveExecutor_whenRequiredExecutorSetWithoutPriorValidation_isTrustedAnywayOnEveryPlatform() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.httpVersion = .http1Only
        configuration.requiredExecutor = .urlSession

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .urlSession)
    }

    // MARK: - requireExecutor(_:)

    @Test
    func requireExecutor_whenNIOPinned_neverThrowsEvenWhenEverythingElseIsIncompatible() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.dnsOverride = ["example.com": "127.0.0.1"]
        configuration.httpVersion = .http1Only

        var secureConnection = Internals.SecureConnection()
        secureConnection.additionalTrustRoots = [.file("/dev/null")]
        secureConnection.pskHint = "hint"
        configuration.secureConnection = secureConnection

        // When / Then
        try configuration.requireExecutor(.nio)
    }

    @Test
    func requireExecutor_whenURLSessionPinnedAndCompatible_doesNotThrow() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)

        var secureConnection = Internals.SecureConnection()
        secureConnection.additionalTrustRoots = [.file("/dev/null")]
        configuration.secureConnection = secureConnection

        // When / Then
        try configuration.requireExecutor(.urlSession)
    }

    @Test
    func requireExecutor_whenURLSessionPinnedAndIncompatible_throwsWithExactReasons() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(.none)
        configuration.dnsOverride = ["example.com": "127.0.0.1"]
        configuration.httpVersion = .http1Only

        // When
        do {
            try configuration.requireExecutor(.urlSession)
            Issue.record("Not expecting success")
        } catch let error as Internals.IncompatibleExecutorConfigurationError {
            // Then
            #expect(error.requiredExecutor == .urlSession)
            #expect(error.reasons == [.dnsOverrideUnderURLSession, .http1OnlyUnderURLSession])
        }
    }

    @Test
    func requireExecutor_whenNIOTransportServicesPinnedAndCompatible_doesNotThrow() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When / Then
        try configuration.requireExecutor(.nioTransportServices)
    }

    @Test
    func requireExecutor_whenNIOTransportServicesPinnedAndIncompatible_throwsWithExactReasons() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        var secureConnection = Internals.SecureConnection()
        secureConnection.additionalTrustRoots = [.file("/dev/null")]
        configuration.secureConnection = secureConnection

        // When
        do {
            try configuration.requireExecutor(.nioTransportServices)
            Issue.record("Not expecting success")
        } catch let error as Internals.IncompatibleExecutorConfigurationError {
            // Then
            #expect(error.requiredExecutor == .nioTransportServices)
            #expect(error.reasons == [.additionalTrustRootsUnderNetworkFramework])
        }
    }
}
