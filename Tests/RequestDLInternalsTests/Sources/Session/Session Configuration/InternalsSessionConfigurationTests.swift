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
