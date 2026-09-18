//
// See LICENSE for this package's licensing information.
//

// The tests that name `.nio`/`.nioTransportServices` (see the main declaration's own doc
// comment, in `InternalsSessionConfigurationExecutorTests.swift`), split out because
// `Internals.Executor.nio`/`.nioTransportServices` only exist under `canImport(NIOCore)`.
#if canImport(NIOCore)

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

extension InternalsSessionConfigurationExecutorTests {

    @Test
    func configuration_whenSecureConnectionIncompatible_reasonsPropagate() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        var secureConnection = Internals.SecureConnection()
        secureConnection.pskHint = "hint"

        // When
        configuration.secureConnection = secureConnection

        // Then
        #expect(configuration.urlSessionIncompatibilityReasons().contains(.pskHint))
    }

    @Test
    func resolveExecutor_whenIncompatibleWithURLSessionOnly_resolvesToNIOTransportServicesOnDarwin() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        // When: fine under NIOTransportServices, unsupported under URLSession (bucket D)
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
        configuration.decompression = .enabled(algorithms: [], limit: .none)
        configuration.httpVersion = .http1Only

        var secureConnection = Internals.SecureConnection()
        secureConnection.cipherSuiteValues = [.TLS_AES_128_GCM_SHA256]
        configuration.secureConnection = secureConnection

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .nio)
    }

    @Test
    func resolveExecutor_whenAdditionalTrustRootsSetAndNIOTransportServicesPreferred_resolvesToItOverURLSession()
        async throws
    {
        // Given: `additionalTrustRoots` alone (no SPKI pinning) doesn't rule out NIOTransportServices,
        // so an explicit preference for it wins instead of falling back to URLSession.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
        configuration.preferredExecutor = .nioTransportServices

        var secureConnection = Internals.SecureConnection()
        secureConnection.additionalTrustRoots = [.file("/dev/null")]
        configuration.secureConnection = secureConnection

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
    func resolveExecutor_whenNoHostnameVerificationSetAndNIOTransportServicesPreferred_resolvesToItOverURLSession()
        async throws
    {
        // Given: `.noHostnameVerification` alone doesn't rule out NIOTransportServices either
        // (`Internals.NIOTrustEvaluator` installs the custom verification callback AsyncHTTPClient's
        // own `precondition` trap otherwise requires), so an explicit preference for it wins.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
        configuration.preferredExecutor = .nioTransportServices

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateVerification = .noHostnameVerification
        configuration.secureConnection = secureConnection

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .nioTransportServices)
        #else
        #expect(sut == .nio)
        #endif
    }

    /// Mirrors `resolveExecutor_whenAdditionalTrustRootsSet_resolvesToURLSessionOnDarwin` (main
    /// file), but for a field that has *no* URLSession-reachable equivalent (no ATS `Info.plist`
    /// key for a maximum TLS version), so it must fall back away from `.urlSession` instead.
    @Test
    func resolveExecutor_whenMaximumTLSVersionSet_resolvesToNIOTransportServicesOnDarwin() async throws {
        // Given: fine under NIOTransportServices, unsupported under URLSession
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)

        var secureConnection = Internals.SecureConnection()
        secureConnection.maximumTLSVersion = .tlsv12
        configuration.secureConnection = secureConnection

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .nioTransportServices)
        #else
        #expect(sut == .nio)
        #endif
    }

    // MARK: - resolveExecutor() with preferredExecutor

    @Test
    func resolveExecutor_whenNIOTransportServicesPreferredAndCompatible_resolvesToItOverURLSession() async throws {
        // Given: compatible with both `.urlSession` and `.nioTransportServices`, so the
        // preference is what breaks the tie rather than falling to the default priority order.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
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
        // Given: compatible with everything, yet `.nio` is explicitly preferred.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
        configuration.preferredExecutor = .nio

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .nio)
    }

    /// A preference the configuration can't actually satisfy is not an override. Resolution must
    /// fall through to whatever the default priority order would have picked among the
    /// compatible candidates, not honor the preference anyway. Here, that's all the way to `.nio`,
    /// since the field used also rules out `.urlSession`.
    ///
    /// There's no longer a field that rules out only `.nioTransportServices` while sparing
    /// `.urlSession`: `additionalTrustRoots` and `.noHostnameVerification` were the last two, and
    /// `Internals.NIOTrustEvaluator` closed both gaps (see the `..._resolvesToItOverURLSession`
    /// tests above). Every remaining incompatible field rejects both executors identically (see
    /// `resolveExecutor_whenIncompatibleWithBothURLSessionAndNIOTransportServices_resolvesToNIO`).
    @Test
    func resolveExecutor_whenNIOTransportServicesPreferredButIncompatible_fallsBackToNIO() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
        configuration.preferredExecutor = .nioTransportServices

        var secureConnection = Internals.SecureConnection()
        secureConnection.cipherSuiteValues = [.TLS_AES_128_GCM_SHA256]
        configuration.secureConnection = secureConnection

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .nio)
    }

    @Test
    func resolveExecutor_whenURLSessionPreferredButIncompatible_fallsBackToNIOTransportServices() async throws {
        // Given: unreachable under URLSession (bucket D), unaffected under NIOTransportServices
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
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
    /// released API that predates `preferredExecutor`; its whole point, historically, was
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
        // Given: compatible with `.urlSession` too, so the implicit preference is what breaks
        // the tie rather than `.urlSession`'s own default priority.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
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

    /// The flag's implicit preference is still just a preference, not a guarantee: a
    /// NIOTransportServices-incompatible field must still fall through past it, the same way an
    /// explicit `preferredExecutor(.nioTransportServices)` already does two tests above this
    /// section (including why the fallback lands on `.nio`, not `.urlSession`).
    @Test
    func resolveExecutor_whenNetworkFrameworkEnabledButIncompatible_fallsThroughToNIO() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
        configuration.enableNetworkFramework = true

        var secureConnection = Internals.SecureConnection()
        secureConnection.cipherSuiteValues = [.TLS_AES_128_GCM_SHA256]
        configuration.secureConnection = secureConnection

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .nio)
    }

    // MARK: - resolveExecutor() with requiredExecutor

    /// Regression coverage for a real bug end-to-end testing caught: `resolveExecutor()`'s own
    /// doc comment already claimed `requiredExecutor` "lets a caller override it," but the
    /// implementation below only ever consulted `preferredExecutor`.
    ///
    /// `requiredExecutor(.nio)` validated (via `requireExecutor(_:)`, called separately) without
    /// ever actually being the executor a real request dispatched over; `resolveExecutor()`
    /// picked `.urlSession` anyway on a compatible config, silently. Caught by a `DataTaskTests`
    /// test pinning `.requiredExecutor(.nio)` to keep a client-cert mTLS test off `.urlSession`'s
    /// unconditional Keychain-Sharing gap, which kept hitting that gap anyway until this was
    /// fixed.
    @Test
    func resolveExecutor_whenNIORequired_resolvesToNIORegardlessOfPreferredExecutorOrCompatibility() async throws {
        // Given: compatible with `.urlSession`, and even prefers it, yet `.nio` is required.
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
        configuration.preferredExecutor = .urlSession
        configuration.requiredExecutor = .nio

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #expect(sut == .nio)
    }

    @Test
    func resolveExecutor_whenURLSessionRequired_resolvesToURLSessionRegardlessOfPreferredExecutor() async throws {
        // Given: `requiredExecutor` is trusted unconditionally, on every platform (see the
        // "without prior validation" test in the main file for why that's fine in practice even
        // here).
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [], limit: .none)
        configuration.preferredExecutor = .nio
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
    func requireExecutor_whenNIOTransportServicesPinnedAndCompatible_doesNotThrow() async throws {
        // Given
        let configuration = Internals.Session.Configuration()

        // When / Then
        try configuration.requireExecutor(.nioTransportServices)
    }

    @Test
    func requireExecutor_whenNIOTransportServicesPinnedAndIncompatible_throwsWithExactReasons() async throws {
        // Given: `keyLogger` (and the rest of "bucket D") stays a genuine Network.framework gap,
        // unlike `additionalTrustRoots`/`.noHostnameVerification`. See the two
        // `..._doesNotThrow` tests below for those.
        var configuration = Internals.Session.Configuration()

        var secureConnection = Internals.SecureConnection()
        secureConnection.cipherSuiteValues = [.TLS_AES_128_GCM_SHA256]
        configuration.secureConnection = secureConnection

        // When
        do {
            try configuration.requireExecutor(.nioTransportServices)
            Issue.record("Not expecting success")
        } catch let error as Internals.IncompatibleExecutorConfigurationError {
            // Then
            #expect(error.requiredExecutor == .nioTransportServices)
            #expect(error.reasons == [.cipherSuiteValues])
        }
    }

    @Test
    func requireExecutor_whenNIOTransportServicesPinnedWithAdditionalTrustRootsOnly_doesNotThrow() async throws {
        // Given: regression coverage for the gap `Internals.NIOTrustEvaluator` closed:
        // `additionalTrustRoots` alone, with no SPKI pinning, used to throw here.
        var configuration = Internals.Session.Configuration()

        var secureConnection = Internals.SecureConnection()
        secureConnection.additionalTrustRoots = [.file("/dev/null")]
        configuration.secureConnection = secureConnection

        // When / Then
        try configuration.requireExecutor(.nioTransportServices)
    }

    @Test
    func requireExecutor_whenNIOTransportServicesPinnedWithNoHostnameVerificationOnly_doesNotThrow() async throws {
        // Given: AsyncHTTPClient's NIOTransportServices bridge traps on `.noHostnameVerification`
        // via `precondition` unless a custom Network.framework verification callback is installed.
        // `Internals.NIOTrustEvaluator` installs exactly that callback whenever
        // `.noHostnameVerification` is configured, and swaps in a hostname-less trust policy
        // inside it, so this doesn't throw.
        var configuration = Internals.Session.Configuration()

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateVerification = .noHostnameVerification
        configuration.secureConnection = secureConnection

        // When / Then
        try configuration.requireExecutor(.nioTransportServices)
    }

    // MARK: - nonURLSessionExecutorIncompatibilityReasons() / early rejection

    @Test
    func requireExecutor_whenNIOPinnedAndURLSessionOnlyAlgorithmConfigured_throws() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [MockURLSessionOnlyAlgorithm()], limit: .none)

        // When
        do {
            try configuration.requireExecutor(.nio)
            Issue.record("Not expecting success")
        } catch let error as Internals.IncompatibleExecutorConfigurationError {
            // Then
            #expect(error.requiredExecutor == .nio)
            #expect(error.reasons == [.decompressionRequiresURLSession])
        }
    }

    @Test
    func requireExecutor_whenNIOTransportServicesPinnedAndURLSessionOnlyAlgorithmConfigured_throws() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [MockURLSessionOnlyAlgorithm()], limit: .none)

        // When
        do {
            try configuration.requireExecutor(.nioTransportServices)
            Issue.record("Not expecting success")
        } catch let error as Internals.IncompatibleExecutorConfigurationError {
            // Then
            #expect(error.requiredExecutor == .nioTransportServices)
            #expect(error.reasons == [.decompressionRequiresURLSession])
        }
    }

    /// Automatic resolution deliberately *degrades* here instead of failing, unlike the
    /// `requireExecutor(_:)` hard-pin tests above: there was no explicit instruction to honor, so
    /// forcing `.urlSession` itself incompatible (`dnsOverride`) still resolves to whatever the
    /// normal fallback order would have picked anyway (`.nioTransportServices` here, since
    /// nothing makes that incompatible either) rather than throwing. The request goes ahead,
    /// and the existing manual-dispatch machinery only ever reports a problem if a `br` response
    /// actually arrives, same as any other `Content-Encoding` this package can't decode. See
    /// `resolveExecutor()`'s own doc comment.
    @Test
    func resolveExecutor_whenURLSessionOnlyAlgorithmConfiguredAndURLSessionAlsoIncompatible_bypassesToNormalFallback()
        async throws
    {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(algorithms: [MockURLSessionOnlyAlgorithm()], limit: .none)
        configuration.dnsOverride = ["example.com": "127.0.0.1"]

        // When
        let sut = configuration.resolveExecutor()

        // Then
        #if canImport(Darwin)
        #expect(sut == .nioTransportServices)
        #else
        #expect(sut == .nio)
        #endif
    }
}

#endif
