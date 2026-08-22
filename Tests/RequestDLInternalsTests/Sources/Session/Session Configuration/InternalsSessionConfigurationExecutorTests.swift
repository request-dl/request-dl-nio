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

    /// §6.1's "not a strict hierarchy" property: a field unsupported under URLSession and a
    /// *different* field unsupported under NIOTransportServices together must fall all the way
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
        // Given -- reachable under URLSession (§6.1), unlike under NIOTransportServices
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

    /// A preference the configuration can't actually satisfy is not an override -- §6.4's whole
    /// point. Resolution must fall through to whatever the default priority order would have
    /// picked among the compatible candidates, not honor the preference anyway.
    @Test
    func resolveExecutor_whenNIOTransportServicesPreferredButIncompatible_fallsBackToURLSession() async throws {
        // Given -- reachable under URLSession (§6.1), unreachable under NIOTransportServices
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
