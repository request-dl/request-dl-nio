//
// See LICENSE for this package's licensing information.
//

import Configuration
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A key that is present with a value of the wrong type is an error, not an absent key. The
/// non-throwing `ConfigReader` getters return `nil` for it, which turned a mistyped
/// `tlsMinimumVersion` or `pins` into a request with no TLS floor and no pinning.
struct ConfiguredTypeMismatchTests {

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    struct Case: Sendable, CustomTestStringConvertible {
        let key: String
        let value: ConfigValue
        let context: ConfiguredError.Context

        var testDescription: String { key }
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    private static let securityCases: [Case] = [
        Case(
            key: "secureConnection.spkiPinning.pins",
            value: .init(.string("a-single-string"), isSecret: false),
            context: .invalidSecureConnectionConfiguration
        ),
        Case(
            key: "secureConnection.spkiPinning.pins",
            value: .init(.intArray([1, 2]), isSecret: false),
            context: .invalidSecureConnectionConfiguration
        ),
        Case(
            key: "secureConnection.tlsMinimumVersion",
            value: .init(.double(1.3), isSecret: false),
            context: .invalidSecureConnectionConfiguration
        ),
        Case(
            key: "secureConnection.tlsMaximumVersion",
            value: .init(.int(1), isSecret: false),
            context: .invalidSecureConnectionConfiguration
        ),
        Case(
            key: "secureConnection.trustRoots",
            value: .init(.int(1), isSecret: false),
            context: .invalidSecureConnectionConfiguration
        ),
        Case(
            key: "secureConnection.additionalTrustRoots",
            value: .init(.bool(true), isSecret: false),
            context: .invalidSecureConnectionConfiguration
        ),
        Case(
            key: "secureConnection.certificates",
            value: .init(.stringArray(["a.pem"]), isSecret: false),
            context: .invalidSecureConnectionConfiguration
        ),
        Case(
            key: "secureConnection.privateKey.file",
            value: .init(.int(1), isSecret: false),
            context: .invalidSecureConnectionConfiguration
        ),
        Case(
            key: "proxy.enabled",
            value: .init(.string("true"), isSecret: false),
            context: .invalidProxyConfiguration
        ),
        Case(
            key: "authorization.scheme",
            value: .init(.int(1), isSecret: false),
            context: .invalidAuthorizationConfiguration
        ),
    ]

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    private static let otherCases: [Case] = [
        Case(key: "baseURL", value: .init(.int(1), isSecret: false), context: .invalidBaseURLConfiguration),
        Case(key: "method", value: .init(.int(1), isSecret: false), context: .invalidConfigurationValue),
        Case(key: "timeout", value: .init(.string("30"), isSecret: false), context: .invalidTimeoutConfiguration),
        Case(key: "headers", value: .init(.string("A: b"), isSecret: false), context: .invalidConfigurationValue),
        Case(key: "queries", value: .init(.string("a=b"), isSecret: false), context: .invalidConfigurationValue),
        Case(key: "dnsOverrides", value: .init(.string("a:b"), isSecret: false), context: .invalidConfigurationValue),
        Case(key: "urlOverrides", value: .init(.string("a|b"), isSecret: false), context: .invalidConfigurationValue),
        Case(key: "systemProxy", value: .init(.string("yes"), isSecret: false), context: .invalidConfigurationValue),
        Case(key: "cachePolicy", value: .init(.int(1), isSecret: false), context: .invalidCachePolicy),
        Case(key: "cacheStrategy", value: .init(.int(1), isSecret: false), context: .invalidCacheStrategy),
        Case(key: "redirect.mode", value: .init(.int(1), isSecret: false), context: .invalidRedirectConfiguration),
        Case(
            key: "maximumConnectionsPerHost",
            value: .init(.string("4"), isSecret: false),
            context: .invalidConfigurationValue
        ),
        Case(
            key: "maximumConcurrentConnections",
            value: .init(.double(4), isSecret: false),
            context: .invalidConfigurationValue
        ),
    ]

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    private func attempt(_ values: [AbsoluteConfigKey: ConfigValue]) async throws {
        let reader = ConfigReader(provider: InMemoryProvider(values: values))

        _ = try await resolve(TestProperty { Configured(reader) })
    }

    @Test(arguments: securityCases + otherCases)
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func value_whenOfTheWrongType_throws(_ testCase: Case) async {
        // When
        let error = await #expect(throws: ConfiguredError.self) {
            try await attempt([AbsoluteConfigKey(stringLiteral: testCase.key): testCase.value])
        }

        // Then
        #expect(error?.context == testCase.context)
    }

    /// The `proxy` and `redirect` keys that are only read after another key turned them on.
    @Test(arguments: [
        Case(key: "proxy.host", value: .init(.int(1), isSecret: false), context: .invalidProxyConfiguration),
        Case(key: "proxy.port", value: .init(.string("8080"), isSecret: false), context: .invalidProxyConfiguration),
        Case(key: "proxy.type", value: .init(.int(1), isSecret: false), context: .invalidProxyConfiguration),
        Case(
            key: "proxy.connectHeaders",
            value: .init(.string("A: b"), isSecret: false),
            context: .invalidProxyConfiguration
        ),
        Case(
            key: "proxy.authorization.scheme",
            value: .init(.int(1), isSecret: false),
            context: .invalidAuthorizationConfiguration
        ),
    ])
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func enabledProxy_whenAKeyIsOfTheWrongType_throws(_ testCase: Case) async {
        // Given
        var values: [AbsoluteConfigKey: ConfigValue] = [
            "proxy.enabled": true,
            "proxy.host": "proxy.example.com",
            "proxy.port": 8_080,
        ]
        values[AbsoluteConfigKey(stringLiteral: testCase.key)] = testCase.value

        // When
        let error = await #expect(throws: ConfiguredError.self) {
            try await attempt(values)
        }

        // Then
        #expect(error?.context == testCase.context)
    }

    @Test(arguments: [
        Case(
            key: "redirect.maxRedirects",
            value: .init(.string("3"), isSecret: false),
            context: .invalidRedirectConfiguration
        ),
        Case(
            key: "redirect.allowCycles",
            value: .init(.string("true"), isSecret: false),
            context: .invalidRedirectConfiguration
        ),
    ])
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func followedRedirect_whenAKeyIsOfTheWrongType_throws(_ testCase: Case) async {
        // Given
        var values: [AbsoluteConfigKey: ConfigValue] = ["redirect.mode": "follow"]
        values[AbsoluteConfigKey(stringLiteral: testCase.key)] = testCase.value

        // When
        let error = await #expect(throws: ConfiguredError.self) {
            try await attempt(values)
        }

        // Then
        #expect(error?.context == testCase.context)
    }

    /// The pinning policy is read once there are pins to apply it to.
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func spkiPinningPolicy_whenOfTheWrongType_throws() async {
        // Given
        let pin = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()

        // When
        let error = await #expect(throws: ConfiguredError.self) {
            try await attempt([
                "secureConnection.spkiPinning.pins": .init(.stringArray([pin]), isSecret: false),
                "secureConnection.spkiPinning.policy": .init(.int(1), isSecret: false),
            ])
        }

        // Then
        #expect(error?.context == .invalidSecureConnectionConfiguration)
    }

    /// The error names the context and nothing else: a value of the wrong type may be a secret.
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func error_doesNotCarryTheValue() async {
        // When
        let error = await #expect(throws: ConfiguredError.self) {
            try await attempt([
                "secureConnection.spkiPinning.pins": .init(.string("super-secret-value"), isSecret: true)
            ])
        }

        // Then
        #expect(!String(describing: error as Any).contains("super-secret-value"))
    }

    // MARK: - Pair lists

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func queries_whenANameRepeats_keepsEveryPairInOrder() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "queries": .init(.stringArray(["tag=a", "page=1", "tag=b"]), isSecret: false)
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("127.0.0.1")
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://127.0.0.1?tag=a&page=1&tag=b")
    }

    @Test(arguments: [
        ("queries", "novalue"),
        ("queries", "=value"),
        ("queries", " =value"),
        ("headers", "NoSeparator"),
        ("headers", ": value"),
        ("dnsOverrides", "example.com"),
        ("dnsOverrides", ":127.0.0.1"),
        ("urlOverrides", "https://a.example.com"),
        ("urlOverrides", "|https://b.example.com"),
    ])
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func pairList_whenAnEntryIsMalformed_throws(_ key: String, _ entry: String) async {
        // When
        let error = await #expect(throws: ConfiguredError.self) {
            try await attempt([
                AbsoluteConfigKey(stringLiteral: key): .init(.stringArray(["valid=1", entry]), isSecret: false)
            ])
        }

        // Then
        #expect(error?.context == .invalidConfigurationValue)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func proxyConnectHeaders_whenAnEntryIsMalformed_throws() async {
        // When
        let error = await #expect(throws: ConfiguredError.self) {
            try await attempt([
                "proxy.enabled": true,
                "proxy.host": "proxy.example.com",
                "proxy.port": 8_080,
                "proxy.connectHeaders": .init(.stringArray(["NoSeparator"]), isSecret: false),
            ])
        }

        // Then
        #expect(error?.context == .invalidProxyConfiguration)
    }

    /// An environment variable that is defined and empty, or that ends in a comma, is read as a
    /// list with an empty element: it says nothing, and is not an error.
    @Test(arguments: [
        ([""], 0),
        (["  ", "\t"], 0),
        (["a=1", ""], 1),
    ])
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func pairList_whenAnEntryIsBlank_isSkipped(_ entries: [String], _ count: Int) async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: ["queries": .init(.stringArray(entries), isSecret: false)])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("127.0.0.1")
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.queries.count == count)
    }

    /// A value with a separator in it, or an empty value, is still a pair.
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func headers_whenTheValueHasASeparatorOrIsEmpty_areKept() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "headers": .init(.stringArray(["Referer: https://a.example.com:8443/x", "X-Empty:"]), isSecret: false)
            ])
        )

        // When
        let resolved = try await resolve(TestProperty { Configured(reader) })

        // Then
        #expect(resolved.requestConfiguration.headers["Referer"] == ["https://a.example.com:8443/x"])
        #expect(resolved.requestConfiguration.headers["X-Empty"] == [""])
    }
}
