//
// See LICENSE for this package's licensing information.
//

import Configuration
import Testing

@testable import RequestDL
@testable import RequestDLInternals

/// The keys `Configured` reads must give the same session configuration every time, and a key that
/// only means something next to another one must not be dropped when that one is missing.
struct ConfiguredStabilityTests {

    // MARK: - Pool key

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func urlOverrides_resolvedRepeatedly_giveASinglePoolKey() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "urlOverrides": .init(
                    .stringArray((0..<8).map { "https://h\($0).example.com|http://127.0.0.1:\(8000 + $0)" }),
                    isSecret: false
                )
            ])
        )

        // When
        var distinct: [Internals.Session.Configuration] = []

        for _ in 0..<50 {
            let configuration = try await resolve(TestProperty { Configured(reader) }).session.configuration

            if !distinct.contains(where: { $0 == configuration }) {
                distinct.append(configuration)
            }
        }

        // Then
        #expect(distinct.count == 1)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func urlOverrideDictionary_builtInAnyOrder_givesTheSamePoolKey() async throws {
        // Given
        let table = (0..<8).map { ("https://h\($0).example.com", "http://127.0.0.1:\(8000 + $0)") }

        // When
        var distinct: [Internals.Session.Configuration] = []

        for shift in 0..<table.count {
            let rotated = Array(table[shift...] + table[..<shift])
            let configuration = try await resolve(
                TestProperty { URLOverride(Dictionary(uniqueKeysWithValues: rotated)) }
            ).session.configuration

            if !distinct.contains(where: { $0 == configuration }) {
                distinct.append(configuration)
            }
        }

        // Then
        #expect(distinct.count == 1)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func proxyConnectHeaders_resolvedRepeatedly_giveASinglePoolKey() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "proxy.enabled": true,
                "proxy.host": "proxy.example.com",
                "proxy.port": 8080,
                "proxy.connectHeaders": .init(
                    .stringArray((0..<8).map { "X-H\($0): v\($0)" }),
                    isSecret: true
                ),
            ])
        )

        // When
        var distinct: [Internals.Session.Configuration] = []

        for _ in 0..<50 {
            let configuration = try await resolve(TestProperty { Configured(reader) }).session.configuration

            if !distinct.contains(where: { $0 == configuration }) {
                distinct.append(configuration)
            }
        }

        // Then
        #expect(distinct.count == 1)
    }

    // MARK: - Keys that depend on another one

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    struct Orphan: Sendable, CustomTestStringConvertible {
        let values: [AbsoluteConfigKey: ConfigValue]
        let context: ConfiguredError.Context
        let name: String

        var testDescription: String { name }
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    private static let orphans: [Orphan] = [
        Orphan(
            values: ["secureConnection.spkiPinning.policy": "strict"],
            context: .invalidSecureConnectionConfiguration,
            name: "pinning policy without pins"
        ),
        Orphan(
            values: ["secureConnection.privateKey.password": "secret"],
            context: .invalidSecureConnectionConfiguration,
            name: "private key password without file"
        ),
        Orphan(
            values: ["secureConnection.privateKey.format": "der"],
            context: .invalidSecureConnectionConfiguration,
            name: "private key format without file"
        ),
        Orphan(
            values: ["authorization.username": "user", "authorization.password": "secret"],
            context: .invalidAuthorizationConfiguration,
            name: "basic credentials without scheme"
        ),
        Orphan(
            values: ["authorization.token": "token"],
            context: .invalidAuthorizationConfiguration,
            name: "token without scheme"
        ),
        Orphan(
            values: ["redirect.maxRedirects": 0],
            context: .invalidRedirectConfiguration,
            name: "maxRedirects without mode"
        ),
        Orphan(
            values: ["redirect.allowCycles": true],
            context: .invalidRedirectConfiguration,
            name: "allowCycles without mode"
        ),
    ]

    @Test(arguments: orphans)
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func keyWithoutTheOneThatEnablesIt_throws(_ orphan: Orphan) async {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: orphan.values))

        // Then
        await #expect(throws: ConfiguredError.self) {
            // When
            do {
                _ = try await resolve(TestProperty { Configured(reader) })
            } catch let error as ConfiguredError {
                #expect(error.context == orphan.context)
                throw error
            }
        }
    }

    // MARK: - Values out of range

    @Test(arguments: [0, -1])
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func maximumConcurrentConnections_belowOne_throws(_ value: Int) async {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: ["maximumConcurrentConnections": .init(.int(value), isSecret: false)]))

        // Then
        await #expect(throws: ConfiguredError.self) {
            // When
            try await resolve(TestProperty { Configured(reader) })
        }
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func negativeMaxRedirects_throws() async {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: ["redirect.mode": "follow", "redirect.maxRedirects": -1])
        )

        // Then
        await #expect(throws: ConfiguredError.self) {
            // When
            try await resolve(TestProperty { Configured(reader) })
        }
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func zeroMaxRedirects_isAccepted() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: ["redirect.mode": "follow", "redirect.maxRedirects": 0])
        )

        // When
        let resolved = try await resolve(TestProperty { Configured(reader) })

        // Then
        #expect(resolved.session.configuration.redirectConfiguration != nil)
    }
}
