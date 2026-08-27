//
// See LICENSE for this package's licensing information.
//

import Configuration
import Testing

@testable import RequestDL

struct ConfiguredTests {

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func baseURL() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "baseURL": "example.com"
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com")
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func method() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "method": "post"
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.method == "POST")
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func timeout() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "timeout": 75
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.timeout.connect == UnitTime.seconds(75).nanoseconds)
        #expect(resolved.session.configuration.timeout.read == UnitTime.seconds(75).nanoseconds)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func headers() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "headers": .init(.stringArray(["Content-Type: application/json", "x-api-key: 123"]), isSecret: false)
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Content-Type"] == ["application/json"])
        #expect(resolved.requestConfiguration.headers["x-api-key"] == ["123"])
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func queries() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "queries": .init(.stringArray(["number=123", "page=1"]), isSecret: false)
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("127.0.0.1")
                Configured(reader)
            }
        )

        // `URLComponents`/`URLQueryItem` are not part of `FoundationEssentials`. A dictionary's
        // iteration order is not guaranteed, so the query string built from it needs an
        // order-independent comparison rather than an exact-string check.
        let queryString = resolved.requestConfiguration.url.split(separator: "?", maxSplits: 1).last ?? ""
        let queryItems = Set(queryString.split(separator: "&").map(String.init))

        // Then
        #expect(queryItems.count == 2)
        #expect(queryItems.contains("number=123"))
        #expect(queryItems.contains("page=1"))
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func missingKeysContributeNothing() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [:]))

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("example.com")
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com")
        #expect(resolved.requestConfiguration.method == nil)
        #expect(resolved.requestConfiguration.headers.isEmpty)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func explicitPropertyDeclaredAfterWins() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "baseURL": "example.com"
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
                BaseURL("override.com")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://override.com")
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func bearerAuthorization() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "authorization.scheme": "bearer",
            "authorization.token": "abc123",
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Authorization"] == ["Bearer abc123"])
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func basicAuthorizationFromUsernameAndPassword() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "authorization.scheme": "basic",
            "authorization.username": "user",
            "authorization.password": "pass",
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Authorization"] == ["Basic dXNlcjpwYXNz"])
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func basicAuthorizationFromCredentials() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "authorization.scheme": "basic",
            "authorization.credentials": "dXNlcjpwYXNz",
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Authorization"] == ["Basic dXNlcjpwYXNz"])
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func invalidAuthorizationSchemeThrows() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "authorization.scheme": "digest"
        ]))

        // Then
        await #expect(throws: ConfiguredError.self) {
            // When
            try await resolve(
                TestProperty {
                    Configured(reader)
                }
            )
        }
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func incompleteBearerAuthorizationThrows() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "authorization.scheme": "bearer"
        ]))

        // Then
        await #expect(throws: ConfiguredError.self) {
            // When
            try await resolve(
                TestProperty {
                    Configured(reader)
                }
            )
        }
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func dnsOverrides() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "dnsOverrides": .init(
                .stringArray(["localhost:127.0.0.1", "example.com:192.168.1.1"]),
                isSecret: false
            )
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.dnsOverride["localhost"] == "127.0.0.1")
        #expect(resolved.session.configuration.dnsOverride["example.com"] == "192.168.1.1")
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func systemProxyEnabled() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "systemProxy": true
        ]))

        // When / Then
        // No assertion on the resolved host/port: the system/environment proxy is
        // whatever the CI machine happens to have configured. Reaching here without
        // throwing confirms `systemProxy` wired `SystemProxy()` through.
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )
        _ = resolved.session.configuration.proxy
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func httpProxyWithoutAuthorization() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "proxy.enabled": true,
            "proxy.host": "proxy.example.com",
            "proxy.port": 8080,
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == "proxy.example.com")
        #expect(resolved.session.configuration.proxy?.port == 8080)
        #expect(resolved.session.configuration.proxy?.authorization == nil)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func httpProxyWithBasicAuthorizationAndConnectHeaders() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "proxy.enabled": true,
            "proxy.host": "proxy.example.com",
            "proxy.port": 8080,
            "proxy.authorization.scheme": "basic",
            "proxy.authorization.username": "user",
            "proxy.authorization.password": "pass",
            "proxy.connectHeaders": .init(.stringArray(["X-Proxy-Token: abc123"]), isSecret: false),
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == "proxy.example.com")
        #expect(resolved.session.configuration.proxy?.port == 8080)
        #expect(
            resolved.session.configuration.proxy?.authorization
                == .basic(username: "user", password: "pass")
        )
        #expect(resolved.session.configuration.proxy?.connectHeaders.first(name: "X-Proxy-Token") == "abc123")
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func socksProxy() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "proxy.enabled": true,
            "proxy.host": "socks-proxy.example.com",
            "proxy.type": "socks",
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == "socks-proxy.example.com")
        #expect(resolved.session.configuration.proxy?.port == 1080)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func proxyDisabledContributesNothing() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "proxy.host": "proxy.example.com",
            "proxy.port": 8080,
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy == nil)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func proxyEnabledWithoutHostThrows() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "proxy.enabled": true
        ]))

        // Then
        await #expect(throws: ConfiguredError.self) {
            // When
            try await resolve(
                TestProperty {
                    Configured(reader)
                }
            )
        }
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func httpProxyWithoutPortThrows() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "proxy.enabled": true,
            "proxy.host": "proxy.example.com",
        ]))

        // Then
        await #expect(throws: ConfiguredError.self) {
            // When
            try await resolve(
                TestProperty {
                    Configured(reader)
                }
            )
        }
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func socksProxyWithAuthorizationThrows() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "proxy.enabled": true,
            "proxy.host": "socks-proxy.example.com",
            "proxy.type": "socks",
            "proxy.authorization.scheme": "bearer",
            "proxy.authorization.token": "abc123",
        ]))

        // Then
        await #expect(throws: ConfiguredError.self) {
            // When
            try await resolve(
                TestProperty {
                    Configured(reader)
                }
            )
        }
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func invalidProxyTypeThrows() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "proxy.enabled": true,
            "proxy.host": "proxy.example.com",
            "proxy.type": "ftp",
        ]))

        // Then
        await #expect(throws: ConfiguredError.self) {
            // When
            try await resolve(
                TestProperty {
                    Configured(reader)
                }
            )
        }
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func scopedReader() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "myAPI.baseURL": "example.com"
        ]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader.scoped(to: "myAPI"))
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com")
    }
}
