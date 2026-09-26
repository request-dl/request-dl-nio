//
// See LICENSE for this package's licensing information.
//

import Crypto
import Testing
import Tracing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

#if canImport(Darwin)
// `URLSessionConfiguration` isn't part of the narrow `import struct Foundation.UUID` this file
// otherwise gets by with; needed only by the Darwin-gated `buildURLSessionConfiguration()`
// tests below.
import Foundation
#endif

/// Only the tests that never call `configuration.build()` (`Output`/`HTTPClient.Configuration`,
/// AsyncHTTPClient, only exist under `canImport(NIOCore)`) stay here, plus the Darwin-gated
/// `buildURLSessionConfiguration()` tests, which need only Darwin, not NIOCore. The rest live in
/// `InternalsSessionConfigurationTests+NIO.swift`.
struct InternalsSessionConfigurationTests {

    /// `Internals.ClientManager` hands a pooled client to any request whose configuration is
    /// `==` to the one it was built for, and `build()` bakes the proxy's `connectHeaders` into
    /// that client. `Internals.Proxy.==` deliberately leaves them out (mirroring upstream's own
    /// `HTTPClient.Configuration.Proxy`), so this is the layer that has to compare them.
    /// Otherwise two sessions sharing a proxy host but sending different `CONNECT` credentials
    /// (e.g. one per tenant/account) reuse each other's client, and the second session's
    /// `CONNECT` goes out with the first session's token.
    @Test
    func configuration_whenOnlyProxyConnectHeadersDiffer_shouldNotBeEqual() async throws {
        // Given
        func configuration(token: String?) -> Internals.Session.Configuration {
            var connectHeaders = Internals.HTTPHeaders()
            if let token {
                connectHeaders.add(name: "X-Proxy-Token", value: token)
            }

            var configuration = Internals.Session.Configuration()
            configuration.proxy = Internals.Proxy(
                host: "proxy.example.com",
                port: 8_080,
                connection: .http,
                authorization: nil,
                connectHeaders: connectHeaders
            )
            return configuration
        }

        // Then
        #expect(configuration(token: "tenant-a") != configuration(token: "tenant-b"))
        #expect(configuration(token: "tenant-a") != configuration(token: nil))
        #expect(configuration(token: "tenant-a") == configuration(token: "tenant-a"))
    }

    @Test
    func configuration_whenNetworkPathConstraintsAllNil_shouldBeNil() async throws {
        // Given
        let configuration = Internals.Session.Configuration()

        // Then
        #expect(configuration.networkPathConstraints == nil)
    }

    @Test
    func configuration_whenAllowsCellularAccessSet_shouldPopulateNetworkPathConstraints() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.allowsCellularAccess = false

        // Then
        #expect(configuration.networkPathConstraints?.allowsCellularAccess == false)
        #expect(configuration.networkPathConstraints?.allowsExpensiveNetworkAccess == nil)
        #expect(configuration.networkPathConstraints?.allowsConstrainedNetworkAccess == nil)
        #expect(configuration.networkPathConstraints?.waitsForConnectivity == nil)
    }

    @Test
    func configuration_whenAllowsExpensiveNetworkAccessSet_shouldPopulateNetworkPathConstraints() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.allowsExpensiveNetworkAccess = false

        // Then
        #expect(configuration.networkPathConstraints?.allowsExpensiveNetworkAccess == false)
    }

    @Test
    func configuration_whenAllowsConstrainedNetworkAccessSet_shouldPopulateNetworkPathConstraints() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.allowsConstrainedNetworkAccess = false

        // Then
        #expect(configuration.networkPathConstraints?.allowsConstrainedNetworkAccess == false)
    }

    @Test
    func configuration_whenWaitsForConnectivitySet_shouldPopulateNetworkPathConstraints() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.waitsForConnectivity = true

        // Then
        #expect(configuration.networkPathConstraints?.waitsForConnectivity == true)
    }

    @Test
    func configuration_whenNetworkFrameworkNotEnabled_isCompatibleWithNetworkFrameworkIsFalse() async throws {
        // Given
        let configuration = Internals.Session.Configuration()

        // Then: `false` regardless of `secureConnection`, since the caller never asked for
        // Network framework in the first place.
        #expect(!configuration.isCompatibleWithNetworkFramework)
    }

    @Test
    func configuration_whenNetworkFrameworkEnabledWithoutSecureConnection_isCompatibleWithNetworkFrameworkIsTrue()
        async throws
    {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.enableNetworkFramework = true

        // Then
        #expect(configuration.isCompatibleWithNetworkFramework)
    }

    @Test
    func configuration_whenNetworkFrameworkEnabledWithSPKIPinning_isCompatibleWithNetworkFrameworkIsTrue()
        async throws
    {
        // Given
        var configuration = Internals.Session.Configuration()
        var secureConnection = Internals.SecureConnection()
        secureConnection.tlsPins = [.init(source: .rawData(.init()), algorithm: SHA256.self)]

        // When
        configuration.enableNetworkFramework = true
        configuration.secureConnection = secureConnection

        // Then: SPKI pinning is enforced under Network.framework too, via
        // `Internals.NIOTrustEvaluator`/`HTTPClient.Configuration.tlsCustomVerificationNetworkFramework`
        // (AsyncHTTPClient's fork, 1.38.0+), so it no longer needs to steer a session off that
        // executor the way it did when pinning only worked through the NIOSSL backend. Network.framework
        // doesn't exist at all off Darwin, so `isCompatibleWithNetworkFramework` itself stays
        // unconditionally `false` there regardless of reasons, checked directly on Darwin, and via
        // the platform-independent reasons list everywhere else.
        #if canImport(Darwin)
        #expect(configuration.isCompatibleWithNetworkFramework)
        #endif
        #expect(secureConnection.networkFrameworkIncompatibilityReasons().isEmpty)
        #expect(secureConnection.tlsPins != nil)
    }

    @Test
    func configuration_whenSetTracer_shouldBeStoredForRequestDLsOwnUse() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        let tracer = RecordingTracer()

        // When
        configuration.tracer = tracer

        // Then
        #expect((configuration.tracer as? RecordingTracer) != nil)
    }

    #if canImport(Darwin)
    /// Regression coverage: `minimumTLSVersion`/`maximumTLSVersion` used to be silently dropped
    /// under `.urlSession`: no `URLSessionConfiguration` counterpart was ever set, despite both
    /// being genuinely reachable via `tlsMinimumSupportedProtocolVersion`/
    /// `tlsMaximumSupportedProtocolVersion` (public API since iOS 13/macOS 10.15, both already
    /// below this package's own deployment floor).
    @Test
    func configuration_whenSecureConnectionSetsTLSVersionRange_urlSessionConfigurationMatches() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        var secureConnection = Internals.SecureConnection()
        secureConnection.minimumTLSVersion = .tlsv12
        secureConnection.maximumTLSVersion = .tlsv13
        configuration.secureConnection = secureConnection

        // When
        let urlSessionConfiguration = configuration.buildURLSessionConfiguration()

        // Then
        #expect(urlSessionConfiguration.tlsMinimumSupportedProtocolVersion == .TLSv12)
        #expect(urlSessionConfiguration.tlsMaximumSupportedProtocolVersion == .TLSv13)
    }

    @Test
    func configuration_whenSecureConnectionOmitsTLSVersionRange_urlSessionConfigurationKeepsSystemDefault()
        async throws
    {
        // Given: absence must stay absence, not get forced to some RequestDL-chosen floor
        let configuration = Internals.Session.Configuration()
        let defaultConfiguration = URLSessionConfiguration.ephemeral

        // When
        let urlSessionConfiguration = configuration.buildURLSessionConfiguration()

        // Then
        #expect(
            urlSessionConfiguration.tlsMinimumSupportedProtocolVersion
                == defaultConfiguration.tlsMinimumSupportedProtocolVersion
        )
        #expect(
            urlSessionConfiguration.tlsMaximumSupportedProtocolVersion
                == defaultConfiguration.tlsMaximumSupportedProtocolVersion
        )
    }

    /// Regression coverage, same bug class as the TLS-version pair above:
    /// `Session.maximumConnectionsPerHost(_:)` reached AsyncHTTPClient's
    /// `concurrentHTTP1ConnectionsPerHostSoftLimit` but was silently dropped under `.urlSession`,
    /// despite `httpMaximumConnectionsPerHost` being an exact counterpart. Since `.urlSession` is
    /// the default executor on Darwin, the modifier did nothing at all for most callers.
    @Test
    func configuration_whenMaximumConnectionsPerHostSet_urlSessionConfigurationMatches() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = 3

        // When
        let urlSessionConfiguration = configuration.buildURLSessionConfiguration()

        // Then
        #expect(urlSessionConfiguration.httpMaximumConnectionsPerHost == 3)
    }

    @Test
    func configuration_whenMaximumConnectionsPerHostOmitted_urlSessionConfigurationKeepsSystemDefault() async throws {
        // Given: absence must stay absence, not get retuned to AsyncHTTPClient's own default
        let configuration = Internals.Session.Configuration()
        let defaultConfiguration = URLSessionConfiguration.ephemeral

        // When
        let urlSessionConfiguration = configuration.buildURLSessionConfiguration()

        // Then
        #expect(
            urlSessionConfiguration.httpMaximumConnectionsPerHost
                == defaultConfiguration.httpMaximumConnectionsPerHost
        )
    }

    #if os(iOS)
    /// Regression coverage: `multipathServiceType` (set via `Session.multipathServiceType(_:)`)
    /// used to have no `.urlSession` counterpart at all -- only `enableMultipath` on the `.nio`
    /// side -- so the setting silently did nothing under `.urlSession`, the default executor on
    /// Darwin. `URLSessionConfiguration.multipathServiceType` itself only exists on iOS (which
    /// Mac Catalyst compiles as) -- not macOS, tvOS, watchOS, or visionOS, confirmed by actual
    /// compiler diagnostics, not just Apple's docs -- so this is gated the same way the
    /// production mapping is.
    @Test(
        arguments: [
            (Internals.MultipathServiceType.handover, URLSessionConfiguration.MultipathServiceType.handover),
            (.interactive, .interactive),
            (.aggregate, .aggregate),
            (.none, .none),
        ] as [(Internals.MultipathServiceType, URLSessionConfiguration.MultipathServiceType)]
    )
    func configuration_whenMultipathServiceTypeSet_urlSessionConfigurationMatches(
        _ multipathServiceType: Internals.MultipathServiceType,
        _ expected: URLSessionConfiguration.MultipathServiceType
    ) async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.multipathServiceType = multipathServiceType

        // When
        let urlSessionConfiguration = configuration.buildURLSessionConfiguration()

        // Then
        #expect(urlSessionConfiguration.multipathServiceType == expected)
    }
    #endif
    #endif
}

/// Not `private`: shared with the `.build()`-dependent tests split out into
/// `InternalsSessionConfigurationTests+NIO.swift`.
struct RecordingTracer: Tracer, Sendable {

    func startSpan<Instant: TracerInstant>(
        _ operationName: String,
        context: @autoclosure () -> ServiceContext,
        ofKind kind: SpanKind,
        at instant: @autoclosure () -> Instant,
        function: String,
        file fileID: String,
        line: UInt
    ) -> NoOpTracer.NoOpSpan {
        NoOpTracer.NoOpSpan(context: context())
    }

    func forceFlush() {}

    func inject<Carrier, Inject>(_ context: ServiceContext, into carrier: inout Carrier, using injector: Inject)
    where Inject: Injector, Carrier == Inject.Carrier {}

    func extract<Carrier, Extract>(_ carrier: Carrier, into context: inout ServiceContext, using extractor: Extract)
    where Extract: Extractor, Carrier == Extract.Carrier {}
}
