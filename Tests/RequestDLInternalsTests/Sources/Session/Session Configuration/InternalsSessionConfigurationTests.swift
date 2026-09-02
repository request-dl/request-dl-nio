//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Crypto
import NIOCore
import Testing
import Tracing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

struct InternalsSessionConfigurationTests {

    @Test
    func configuration_whenSetTLSConfiguration_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        let secureConnection = Internals.SecureConnection()

        // When
        configuration.secureConnection = secureConnection

        let builtConfiguration = try configuration.build()

        // Then
        #expect(
            try builtConfiguration.tlsConfiguration?.bestEffortEquals(
                secureConnection.build().tlsConfiguration
            ) ?? false
        )
    }

    @Test
    func configuration_whenSetRedirectConfiguration_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        let redirectConfiguration = Internals.RedirectConfiguration.disallow

        // When
        configuration.redirectConfiguration = redirectConfiguration

        let builtConfiguration = try configuration.build()

        // Then
        #expect(
            String(
                describing: builtConfiguration.redirectConfiguration
            )
                == String(
                    describing: redirectConfiguration.build()
                )
        )
    }

    @Test
    func configuration_whenSetTimeout_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let connect: Int64 = 60_000_000_000
        let read: Int64 = 60_000_000_000

        let timeout = Internals.Timeout(
            connect: connect,
            read: read
        )

        // When
        configuration.timeout = timeout

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.timeout.connect == .nanoseconds(connect))
        #expect(builtConfiguration.timeout.read == .nanoseconds(read))
    }

    @Test
    func configuration_whenSetConnectionPool_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let connectionPool = HTTPClient.Configuration.ConnectionPool(idleTimeout: .seconds(16))

        // When
        configuration.connectionPool = connectionPool

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.connectionPool == connectionPool)
    }

    @Test
    func configuration_whenSetHTTPProxyWith_shoudlBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: nil
        )

        // When
        configuration.proxy = proxy

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.proxy?.host == proxy.host)
        #expect(builtConfiguration.proxy?.port == proxy.port)
        #expect(builtConfiguration.proxy?.authorization == nil)
    }

    @Test
    func configuration_whenSetHTTPProxyWithAuthorization_shoudlBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let username = UUID().uuidString
        let password = UUID().uuidString

        let proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: .basic(username: username, password: password)
        )

        // When
        configuration.proxy = proxy

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.proxy?.host == proxy.host)
        #expect(builtConfiguration.proxy?.port == proxy.port)
        #expect(builtConfiguration.proxy?.authorization == .basic(username: username, password: password))
    }

    @Test
    func configuration_whenSetHTTPProxyWithRawAuthorization_shoudlBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let credentials = UUID().uuidString

        let proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: .basicRawCredentials(credentials)
        )

        // When
        configuration.proxy = proxy

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.proxy?.host == proxy.host)
        #expect(builtConfiguration.proxy?.port == proxy.port)
        #expect(builtConfiguration.proxy?.authorization == .basic(credentials: credentials))
    }

    @Test
    func configuration_whenSetSOCKSProxy_shoudlBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .socks,
            authorization: nil
        )

        // When
        configuration.proxy = proxy

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.proxy?.host == proxy.host)
        #expect(builtConfiguration.proxy?.port == proxy.port)
        #expect(builtConfiguration.proxy?.authorization == nil)
    }

    @Test
    func configuration_whenSetDecompression_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let decompression = Internals.Decompression.enabled(.size(16))

        // When
        configuration.decompression = decompression

        let builtConfiguration = try configuration.build()

        // Then
        #expect(
            String(
                describing: builtConfiguration.decompression
            )
                == String(
                    describing: decompression.build()
                )
        )
    }

    @Test
    func configuration_whenSetHttpVersion_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let version = Internals.HTTPVersion.http1Only

        // When
        configuration.httpVersion = version

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.httpVersion == version.build())
    }

    @Test(arguments: [
        Internals.MultipathServiceType.handover,
        .interactive,
        .aggregate,
    ])
    func configuration_whenSetMultipathServiceType_shouldForwardEnableMultipath(
        _ multipathServiceType: Internals.MultipathServiceType
    ) async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        // When
        configuration.multipathServiceType = multipathServiceType

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.enableMultipath)
    }

    @Test
    func configuration_whenMultipathServiceTypeNone_shouldNotEnableMultipath() async throws {
        // Given
        let configuration = Internals.Session.Configuration()

        // When
        let builtConfiguration = try configuration.build()

        // Then
        #expect(!builtConfiguration.enableMultipath)
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

        // Then -- `false` regardless of `secureConnection`, since the caller never asked for
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
    func configuration_whenNetworkFrameworkEnabledWithSPKIPinning_isCompatibleWithNetworkFrameworkIsFalse()
        async throws
    {
        // Given
        var configuration = Internals.Session.Configuration()
        var secureConnection = Internals.SecureConnection()
        secureConnection.tlsPins = [.init(source: .rawData(.init()), algorithm: SHA256.self)]

        // When
        configuration.enableNetworkFramework = true
        configuration.secureConnection = secureConnection

        // Then -- SPKI pinning silently overrides the Network framework request rather than
        // failing outright or dropping the pins: AsyncHTTPClient's NIOTransportServices bridge
        // never consults `SPKIPinningConfiguration`, so honoring `enableNetworkFramework` here
        // would mean the pins stop being enforced without any signal to the caller.
        #expect(!configuration.isCompatibleWithNetworkFramework)
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

    @Test
    func configuration_whenSetTracer_shouldNotReachAsyncHTTPClientsOwnTracing() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.tracer = RecordingTracer()

        // When
        let builtConfiguration = try configuration.build()

        // Then -- `async-http-client`'s own tracing is always suppressed; RequestDL owns the span
        // lifecycle itself (see the doc comment on `Configuration.tracer`).
        #expect((builtConfiguration.tracing.tracer as? NoOpTracer) != nil)
    }

    @Test
    func configuration_whenTracerNotSet_shouldDefaultToNoOp() async throws {
        // Given
        let configuration = Internals.Session.Configuration()

        // Then
        #expect((configuration.tracer as? NoOpTracer) != nil)
        #expect((try configuration.build().tracing.tracer as? NoOpTracer) != nil)
    }

    @Test
    func configuration_whenInit_shouldBeDefault() async throws {
        // When
        let configuration = Internals.Session.Configuration()
        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.tlsConfiguration == nil)
        #expect(
            String(
                describing: builtConfiguration.redirectConfiguration
            )
                == String(
                    describing: HTTPClient.Configuration.RedirectConfiguration.follow(max: 5, allowCycles: false)
                )
        )
        #expect(builtConfiguration.timeout.connect == nil)
        #expect(builtConfiguration.timeout.read == nil)
        #expect(builtConfiguration.proxy == nil)
        #if canImport(Darwin)
        let expectedDecompression = HTTPClient.Decompression.enabled(limit: .none)
        #else
        let expectedDecompression = HTTPClient.Decompression.disabled
        #endif

        #expect(
            String(
                describing: builtConfiguration.decompression
            )
                == String(
                    describing: expectedDecompression
                )
        )
        #expect(builtConfiguration.httpVersion == .automatic)
        #expect(!builtConfiguration.enableMultipath)
    }
}

private struct RecordingTracer: Tracer, Sendable {

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
