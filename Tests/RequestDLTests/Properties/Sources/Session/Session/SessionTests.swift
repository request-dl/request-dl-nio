//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOPosix
import RequestDLInternals
import Testing
import Tracing

@testable import RequestDL

struct SessionTests {

    @Test
    func session_whenInitAsDefault_shouldBeValid() async throws {
        // Given
        let property = Session()
        let configuration = Internals.Session.Configuration()

        // When
        let resolved = try await resolve(TestProperty { property })
        let sut = resolved.session.configuration

        // Then
        #expect(sut.connectionPool == configuration.connectionPool)
        #expect(sut.redirectConfiguration == nil)
        #expect(sut.timeout.connect == configuration.timeout.connect)
        #expect(sut.timeout.read == configuration.timeout.read)
        #expect(sut.proxy == configuration.proxy)
        #expect(
            String(describing: sut.decompression) == String(describing: configuration.decompression)
        )
        #expect(sut.connectionPool == configuration.connectionPool)
        #expect(sut.allowsCellularAccess == nil)
        #expect(sut.allowsExpensiveNetworkAccess == nil)
        #expect(sut.allowsConstrainedNetworkAccess == nil)
        #expect(sut.waitsForConnectivity == nil)
        #expect(sut.multipathServiceType == .none)
        #expect(sut.networkPathConstraints == nil)
    }

    @Test
    func session_whenInitWithIdentifier_shouldBeValid() async throws {
        // Given
        let property = Session("other", numberOfThreads: 10)
        let options = SessionProviderOptions(
            isCompatibleWithNetworkFramework: true
        )

        // When
        let sut = property.provider

        // Then
        #if canImport(Darwin)
        #expect(sut.uniqueIdentifier(with: options) == "NTW.other.10")
        #else
        #expect(sut.uniqueIdentifier(with: options) == "other.10")
        #endif
        #expect(sut is Internals.IdentifiedSessionProvider)
    }

    @Test
    func session_whenInitWithEventLoopGroup_shouldBeValid() async throws {
        // Given
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let property = Session(eventLoopGroup)
        let options = SessionProviderOptions(
            isCompatibleWithNetworkFramework: true
        )

        // When
        let sut = property.provider

        // Then
        #expect(sut.uniqueIdentifier(with: options) == String(describing: ObjectIdentifier(eventLoopGroup)))
        #expect(sut.group(with: .init(isCompatibleWithNetworkFramework: true)) === eventLoopGroup)
    }

    @Test
    func session_whenWaitsForConnectivity_shouldBeValid() async throws {
        // Given
        let waitsForConnectivity = true

        let property = Session()
            .waitsForConnectivity(waitsForConnectivity)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.waitsForConnectivity == waitsForConnectivity)
    }

    @Test
    func session_whenAllowsCellularAccess_shouldBeValid() async throws {
        // Given
        let allowsCellularAccess = false

        let property = Session()
            .allowsCellularAccess(allowsCellularAccess)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.allowsCellularAccess == allowsCellularAccess)
    }

    @Test
    func session_whenAllowsExpensiveNetworkAccess_shouldBeValid() async throws {
        // Given
        let allowsExpensiveNetworkAccess = false

        let property = Session()
            .allowsExpensiveNetworkAccess(allowsExpensiveNetworkAccess)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.allowsExpensiveNetworkAccess == allowsExpensiveNetworkAccess)
    }

    @Test
    func session_whenAllowsConstrainedNetworkAccess_shouldBeValid() async throws {
        // Given
        let allowsConstrainedNetworkAccess = false

        let property = Session()
            .allowsConstrainedNetworkAccess(allowsConstrainedNetworkAccess)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.allowsConstrainedNetworkAccess == allowsConstrainedNetworkAccess)
    }

    @Test
    func session_whenMultipathServiceType_shouldBeValid() async throws {
        // Given
        let multipathServiceType = Session.MultipathServiceType.handover

        let property = Session()
            .multipathServiceType(multipathServiceType)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.multipathServiceType == multipathServiceType.build())
    }

    @Test
    func session_whenMaxConnectionsPerHost_shouldBeValid() async throws {
        // Given
        let maximumConnections = 10

        let property = Session()
            .maximumConnectionsPerHost(maximumConnections)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(
            resolved.session.configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit
                == maximumConnections
        )
    }

    @Test
    func session_whenMaxConcurrentConnections_shouldBeValid() async throws {
        // Given
        let maximumConcurrentConnections = 4

        let property = Session()
            .maximumConcurrentConnections(maximumConcurrentConnections)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(
            resolved.session.configuration.maximumConcurrentConnections == maximumConcurrentConnections
        )
    }

    @Test
    func session_whenDisableRedirect_shouldBeValid() async throws {
        // Given
        let property = Session()
            .disableRedirect()

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        guard let redirectConfiguration = resolved.session.configuration.redirectConfiguration else {
            Issue.record("Redirect Configuration is nil")
            return
        }

        #expect(
            redirectConfiguration == .disallow
        )
    }

    @Test
    func session_whenEnableRedirect_shouldBeValid() async throws {
        // Given
        let max = 1_000
        let cycles = true

        let property = Session()
            .enableRedirectFollow(max: max, allowCycles: cycles)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        guard let redirectConfiguration = resolved.session.configuration.redirectConfiguration else {
            Issue.record("Redirect Configuration is nil")
            return
        }

        #expect(
            redirectConfiguration
                == .follow(
                    max: max,
                    allowCycles: cycles
                )
        )
    }

    @Test
    func session_whenRedirectStrategy_shouldBeValid() async throws {
        // Given
        struct DummyStrategy: RedirectStrategy {
            func redirectDecision(for context: RedirectContext) throws -> RedirectDecision {
                .doNotFollow
            }
        }

        let property = Session()
            .redirectStrategy(DummyStrategy())

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        guard let redirectConfiguration = resolved.session.configuration.redirectConfiguration else {
            Issue.record("Redirect Configuration is nil")
            return
        }

        guard case .strategy = redirectConfiguration else {
            Issue.record("Expected .strategy, got \(redirectConfiguration)")
            return
        }
    }

    @Test
    func session_whenOnRedirect_shouldBeValid() async throws {
        // Given
        let property = Session()
            .onRedirect { _ in .doNotFollow }

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        guard let redirectConfiguration = resolved.session.configuration.redirectConfiguration else {
            Issue.record("Redirect Configuration is nil")
            return
        }

        guard case .strategy = redirectConfiguration else {
            Issue.record("Expected .strategy, got \(redirectConfiguration)")
            return
        }
    }

    @Test
    func session_whenDecompressionDisabled_shouldBeValid() async throws {
        // Given
        let property = Session()
            .disableDecompression()

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(
            String(
                describing: resolved.session.configuration.decompression
            )
                == String(
                    describing: HTTPClient.Decompression.disabled
                )
        )
    }

    @Test
    func session_whenDecompressionLimit_shouldBeValid() async throws {
        // Given
        let decompressionLimit = Session.DecompressionLimit.ratio(5_000)
        let property = Session()
            .decompressionLimit(decompressionLimit)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(
            resolved.session.configuration.decompression == .enabled(decompressionLimit.build())
        )
    }

    @Test
    func session_whenDecompressionLimitNone_shouldBeValid() async throws {
        // Given
        let decompressionLimit = Session.DecompressionLimit.none
        let property = Session()
            .decompressionLimit(decompressionLimit)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(
            resolved.session.configuration.decompression == .enabled(decompressionLimit.build())
        )
    }

    @Test
    func session_whenDecompressionLimitSize_shouldBeValid() async throws {
        // Given
        let decompressionLimit = Session.DecompressionLimit.size(1_024)
        let property = Session()
            .decompressionLimit(decompressionLimit)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(
            resolved.session.configuration.decompression == .enabled(decompressionLimit.build())
        )
    }

    @Test
    func session_whenCompressionDefault_shouldBeDisabled() async throws {
        // Given
        let property = Session()

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.compression == .disabled)
    }

    @Test
    func session_whenCompressionGzip_shouldBeValid() async throws {
        // Given
        let algorithm = Session.CompressionAlgorithm.gzip
        let property = Session()
            .compression(algorithm)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.compression == .enabled(algorithm.build()))
    }

    @Test
    func session_whenCompressionDeflate_shouldBeValid() async throws {
        // Given
        let algorithm = Session.CompressionAlgorithm.deflate
        let property = Session()
            .compression(algorithm)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.compression == .enabled(algorithm.build()))
    }

    @Test
    func session_whenPreferredExecutor_shouldBeValid() async throws {
        // Given
        let property = Session()
            .preferredExecutor(.nioTransportServices)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.preferredExecutor == .nioTransportServices)
        #expect(resolved.session.configuration.requiredExecutor == nil)
    }

    @Test
    func session_whenRequiredExecutor_shouldBeValid() async throws {
        // Given
        let property = Session()
            .requiredExecutor(.urlSession)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.requiredExecutor == .urlSession)
        #expect(resolved.session.configuration.preferredExecutor == nil)
    }

    @Test
    func session_whenTracerDefault_shouldBeNoOp() async throws {
        // Given
        let property = Session()

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect((resolved.session.configuration.tracer as? NoOpTracer) != nil)
    }

    @Test
    func session_whenTracerSet_shouldBeValid() async throws {
        // Given
        let tracer = RecordingTracer()

        let property = Session()
            .tracer(tracer)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect((resolved.session.configuration.tracer as? RecordingTracer) != nil)

        // `async-http-client`'s own built-in tracing is always suppressed -- RequestDL owns the
        // span lifecycle itself, in `RawTask.result()`, using `resolved.session.configuration
        // .tracer` directly.
        #expect(try (resolved.session.configuration.build().tracing.tracer as? NoOpTracer) != nil)
    }

    @Test
    func session_whenNeverBody_shouldBeNever() async throws {
        // Given
        let property = Session()

        // Then
        try await assertNever(property.body)
    }

    @Test
    func session_whenCollidesPrefersLastDeclared() async throws {
        // Given
        let property = TestProperty {
            Session()
                .decompressionLimit(.size(200))
            Session()
                .waitsForConnectivity(true)
        }

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(resolved.session.configuration.decompression == .enabled(.size(200)))
        #expect(resolved.session.configuration.waitsForConnectivity == true)
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
