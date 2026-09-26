//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

/// Only the tests that never name `.nio`/`.nioTransportServices` (`Internals.Executor` cases
/// that only exist under `canImport(NIOCore)`, see that type's own doc comment) and never touch
/// `SecureConnection.pskHint` (also gated the same way): these keep compiling under
/// `--disable-default-traits`. The rest live in
/// `InternalsSessionConfigurationExecutorTests+NIO.swift`, which needs `NIOCore` to exist at
/// all.
struct InternalsSessionConfigurationExecutorTests {

    /// A stand-in for `BrotliURLSessionOnlyAlgorithm`: that concrete type lives in `RequestDL`,
    /// which this target doesn't depend on, so `Internals.Session.Configuration
    /// .nonURLSessionExecutorIncompatibilityReasons()` is exercised here against any
    /// `Internals.DecompressionAlgorithm` answering `requiresURLSession: true`, matching how
    /// `InternalsDecompressionAlgorithmAdapter` (in `RequestDL`) actually produces that answer,
    /// via `algorithm is BrotliURLSessionOnlyAlgorithm`, not a public protocol requirement.
    ///
    /// Not `private`: shared with the `.nio`/`.nioTransportServices` tests split out into
    /// `InternalsSessionConfigurationExecutorTests+NIO.swift`.
    struct MockURLSessionOnlyAlgorithm: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "br" }
        var requiresURLSession: Bool { true }
        func callAsFunction() throws -> any Internals.DecompressorStream {
            fatalError("not exercised")
        }
    }

    @Test
    func configuration_whenNothingSet_urlSessionIncompatibilityReasonsIsEmpty() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().isEmpty)
    }

    @Test
    func configuration_whenDNSOverrideSet_containsReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        // When
        configuration.dnsOverride = ["example.com": "127.0.0.1"]

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.dnsOverrideUnderURLSession))
    }

    @Test
    func configuration_whenHTTP1OnlySet_containsReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        // When
        configuration.httpVersion = .http1Only

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.http1OnlyUnderURLSession))
    }

    @Test
    func configuration_whenAutomaticHTTPVersionSet_doesNotContainReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        // When
        configuration.httpVersion = .automatic

        // Then
        #expect(!configuration.urlSessionIncompatibilityReasons().contains(.http1OnlyUnderURLSession))
    }

    @Test
    func configuration_whenProxyConnectHeadersSet_containsReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        var connectHeaders = Internals.HTTPHeaders()
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
        configuration.decompression = .enabled(algorithms: [], limit: .none)

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
    }

    /// A SOCKS proxy is reachable under `.urlSession` via `connectionProxyDictionary`'s legacy
    /// `SOCKSEnable`/`SOCKSProxy`/`SOCKSPort` keys. Confirmed empirically (a bare `NWListener`
    /// probe, `InternalsSOCKSProxyDictionaryPlatformTests`, shows `URLSession` genuinely dials the
    /// configured address) before removing this from the exclusion list, not assumed from the
    /// original analysis's "unreliable/undocumented" framing.
    @Test
    func configuration_whenSOCKSProxySet_doesNotContainReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        // When
        configuration.proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .socks,
            authorization: nil
        )

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().isEmpty)
    }

    @Test
    func configuration_whenProxyBearerAuthorizationSet_containsReason() async throws {
        // Given: no `URLCredential` shape can carry an arbitrary bearer token, unlike
        // `.basic`/`.basicRawCredentials`, which map onto the proxy authentication challenge
        // delegate cleanly.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

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
        configuration.decompression = .enabled(algorithms: [], limit: .none)

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
    func configuration_whenDecompressionDisabled_doesNotContainReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.decompression = .disabled

        // Then: `.disabled` gets real parity with NIO on `.urlSession` now, via
        // `Accept-Encoding: identity` at request-build time, so it no longer disqualifies the
        // executor the way it used to.
        #expect(configuration.urlSessionIncompatibilityReasons().isEmpty)
    }

    @Test
    func configuration_whenDecompressionEnabled_doesNotContainReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().isEmpty)
    }

    // MARK: - resolveExecutor()

    // `.nio` in the `#else` branches below only compiles where NIOCore does (a non-Darwin
    // default-trait build); on Darwin only the `#if canImport(Darwin)` branch is ever compiled,
    // regardless of whether NIOCore is available, so these three stay portable unmodified.

    @Test
    func resolveExecutor_whenNothingSet_resolvesToURLSessionOnDarwin() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

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
    func resolveExecutor_whenAdditionalTrustRootsSet_resolvesToURLSessionOnDarwin() async throws {
        // Given: reachable under both URLSession and NIOTransportServices (the latter via
        // `Internals.NIOTrustEvaluator`), so this exercises the default priority order
        // (URLSession first) rather than URLSession being the only compatible option.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

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

    /// `minimumTLSVersion` has a real equivalent under URLSession (an ATS
    /// `NSExceptionMinimumTLSVersion` entry in the app's Info.plist), so it must never force a
    /// fallback away from `.urlSession` -- the same is now true of `maximumTLSVersion`, which maps
    /// directly onto `tlsMaximumSupportedProtocolVersion` (see
    /// `resolveExecutor_whenMaximumTLSVersionSet_resolvesToURLSessionOnDarwin` in
    /// `InternalsSessionConfigurationExecutorTests+NIO.swift`); only `applicationProtocols` (ALPN)
    /// has no such equivalent and still forces the fallback.
    @Test
    func resolveExecutor_whenMinimumTLSVersionSet_resolvesToURLSessionOnDarwin() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        var secureConnection = Internals.SecureConnection()
        secureConnection.minimumTLSVersion = .tlsv12
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
    func resolveExecutor_whenNetworkFrameworkEnabledAndURLSessionExplicitlyPreferred_explicitPreferenceWins()
        async throws
    {
        // Given: an explicit `preferredExecutor` (any case) always outranks the implicit one
        // `enableNetworkFramework` contributes.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
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

    // MARK: - resolveExecutor() with requiredExecutor

    /// `resolveExecutor()` trusts `requiredExecutor` unconditionally and platform-independently
    /// by design (see its own doc comment): the compatibility check already happened, and
    /// already threw, in `requireExecutor(_:)`.
    ///
    /// This test documents that trust rather than re-deriving it: a config `requiredExecutor`
    /// claims is `.urlSession`-compatible despite `httpVersion == .http1Only` (a genuine
    /// bucket-D exclusion) still resolves to `.urlSession` here, because nothing calls
    /// `requireExecutor(_:)` in this test to catch the mismatch first, exactly mirroring what a
    /// caller who skips that call gets in production too.
    @Test
    func resolveExecutor_whenRequiredExecutorSetWithoutPriorValidation_isTrustedAnywayOnEveryPlatform() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
        configuration.httpVersion = .http1Only
        configuration.requiredExecutor = .urlSession

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .urlSession)
    }

    // MARK: - requireExecutor(_:)

    @Test
    func requireExecutor_whenURLSessionPinnedAndCompatible_doesNotThrow() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

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
        configuration.decompression = .enabled(algorithms: [], limit: .none)
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

    // MARK: - nonURLSessionExecutorIncompatibilityReasons() / early rejection

    @Test
    func configuration_whenNoURLSessionOnlyAlgorithmConfigured_nonURLSessionReasonsIsEmpty() async throws {
        // Given
        let configuration = Internals.Session.Configuration()

        // Then
        #expect(configuration.nonURLSessionExecutorIncompatibilityReasons().isEmpty)
    }

    @Test
    func configuration_whenURLSessionOnlyAlgorithmConfigured_containsReason() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [MockURLSessionOnlyAlgorithm()], limit: .none)

        // Then
        #expect(configuration.nonURLSessionExecutorIncompatibilityReasons() == [.decompressionRequiresURLSession])
    }

    @Test
    func requireExecutor_whenURLSessionPinnedAndURLSessionOnlyAlgorithmConfigured_doesNotThrow() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [MockURLSessionOnlyAlgorithm()], limit: .none)

        // When / Then: the one executor such an algorithm actually requires is, naturally,
        // still fine with it.
        try configuration.requireExecutor(.urlSession)
    }

    /// The soft/automatic-resolution counterpart to the hard-pin tests in the `+NIO` half: with
    /// nothing else making `.urlSession` incompatible, resolution should still just pick it, same
    /// as any other compatible configuration.
    @Test
    func resolveExecutor_whenURLSessionOnlyAlgorithmConfiguredAndURLSessionOtherwiseCompatible_resolvesToURLSession()
        async throws
    {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [MockURLSessionOnlyAlgorithm()], limit: .none)

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .urlSession)
        #endif
    }
}
