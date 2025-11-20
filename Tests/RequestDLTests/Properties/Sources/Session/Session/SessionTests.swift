/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import AsyncHTTPClient
import NIOPosix
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
        #expect(sut.ignoreUncleanSSLShutdown == configuration.ignoreUncleanSSLShutdown)
        #expect(
            String(describing: sut.decompression) == String(describing: configuration.decompression)
        )
        #expect(sut.connectionPool == configuration.connectionPool)
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
        #expect(
            try resolved.session.configuration.build().networkFrameworkWaitForConnectivity == waitsForConnectivity
        )
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
            resolved.session.configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit == maximumConnections
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
            redirectConfiguration == .follow(
                max: max,
                allowCycles: cycles
            )
        )
    }

    @Test
    func session_whenIgnoreUncleanSSLShutdown_shouldBeValid() async throws {
        // Given
        let property = Session()
            .ignoreUncleanSSLShutdown()

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(resolved.session.configuration.ignoreUncleanSSLShutdown)
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
            ) == String(
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
    func session_whenDNSOverride_shouldBeValid() async throws {
        // Given
        let origin = "google.com"
        let destination = "apple.com"

        let property = Session()
            .overrideDNS(destination, from: origin)

        // When
        let resolved = try await resolve(TestProperty { property })

        // Then
        #expect(
            try resolved.session.configuration.build().dnsOverride == [origin: destination]
        )
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
        #expect(resolved.session.configuration.networkFrameworkWaitForConnectivity == true)
    }
}
