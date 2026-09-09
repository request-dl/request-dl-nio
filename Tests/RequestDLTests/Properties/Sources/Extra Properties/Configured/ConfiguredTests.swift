//
// See LICENSE for this package's licensing information.
//

import Configuration
import Crypto
import NIOSSL
import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

struct ConfiguredTests {

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func baseURL() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "baseURL": "https://example.com"
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "method": "post"
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "timeout": 75
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "headers": .init(.stringArray(["Content-Type: application/json", "x-api-key: 123"]), isSecret: false)
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "queries": .init(.stringArray(["number=123", "page=1"]), isSecret: false)
            ])
        )

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
    func baseURLRelativePathAppendsToExistingBaseURL() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "baseURL": "users/123"
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.example.com")
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://api.example.com/users/123")
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func baseURLCompleteURLOverridesExistingBaseURL() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "baseURL": "https://override.example.com/v2"
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.example.com")
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://override.example.com/v2")
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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "baseURL": "https://example.com"
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "authorization.scheme": "bearer",
                "authorization.token": "abc123",
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "authorization.scheme": "basic",
                "authorization.username": "user",
                "authorization.password": "pass",
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "authorization.scheme": "basic",
                "authorization.credentials": "dXNlcjpwYXNz",
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "authorization.scheme": "digest"
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "authorization.scheme": "bearer"
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "dnsOverrides": .init(
                    .stringArray(["localhost:127.0.0.1", "example.com:192.168.1.1"]),
                    isSecret: false
                )
            ])
        )

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
    func urlOverrides() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "urlOverrides": .init(
                    .stringArray(["https://google.com|https://apple.com"]),
                    isSecret: false
                )
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://apple.com")
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func urlOverridesWithPathPrefix() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "urlOverrides": .init(
                    .stringArray(["https://google.com/api/v1|https://apple.com/v2"]),
                    isSecret: false
                )
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                Path("api/v1/users")
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://apple.com/v2/users")
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func systemProxyEnabled() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "systemProxy": true
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "proxy.enabled": true,
                "proxy.host": "proxy.example.com",
                "proxy.port": 8080,
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "proxy.enabled": true,
                "proxy.host": "proxy.example.com",
                "proxy.port": 8080,
                "proxy.authorization.scheme": "basic",
                "proxy.authorization.username": "user",
                "proxy.authorization.password": "pass",
                "proxy.connectHeaders": .init(.stringArray(["X-Proxy-Token: abc123"]), isSecret: false),
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "proxy.enabled": true,
                "proxy.host": "socks-proxy.example.com",
                "proxy.type": "socks",
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "proxy.host": "proxy.example.com",
                "proxy.port": 8080,
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "proxy.enabled": true
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "proxy.enabled": true,
                "proxy.host": "proxy.example.com",
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "proxy.enabled": true,
                "proxy.host": "socks-proxy.example.com",
                "proxy.type": "socks",
                "proxy.authorization.scheme": "bearer",
                "proxy.authorization.token": "abc123",
            ])
        )

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
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "proxy.enabled": true,
                "proxy.host": "proxy.example.com",
                "proxy.type": "ftp",
            ])
        )

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
    func cachePolicyMemory() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "cachePolicy": "memory"
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cachePolicy == .memory)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func cachePolicyDisk() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "cachePolicy": "disk"
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cachePolicy == .disk)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func cachePolicyAll() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "cachePolicy": "all"
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cachePolicy == .all)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func invalidCachePolicyThrows() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "cachePolicy": "ssd"
            ])
        )

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

    @Test(
        arguments: [
            ("ignoreCachedData", CacheStrategy.ignoreCachedData),
            ("reloadAndValidateCachedData", CacheStrategy.reloadAndValidateCachedData),
            ("returnCachedDataElseLoad", CacheStrategy.returnCachedDataElseLoad),
            ("useCachedDataOnly", CacheStrategy.useCachedDataOnly),
        ]
    )
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func cacheStrategy(value: String, expected: CacheStrategy) async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "cacheStrategy": .init(.string(value), isSecret: false)
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cacheStrategy == expected)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func invalidCacheStrategyThrows() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "cacheStrategy": "ignoreEverything"
            ])
        )

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
    func secureConnectionTrustRoots() async throws {
        // Given
        let file = UUID().uuidString
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.trustRoots": .init(.string(file), isSecret: false)
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(!(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true))
        #expect(resolved.session.configuration.secureConnection?.trustRoots == .file(file))
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func secureConnectionAdditionalTrustRoots() async throws {
        // Given
        let file = UUID().uuidString
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.additionalTrustRoots": .init(.string(file), isSecret: false)
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.additionalTrustRoots
                == .init([.file(file)])
        )
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func secureConnectionCertificates() async throws {
        // Given
        let file = UUID().uuidString
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.certificates": .init(.string(file), isSecret: false)
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.secureConnection?.certificateChain == .file(file))
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func secureConnectionSPKIPinningDefaultsToStrictPolicy() async throws {
        // Given
        let pin1 = UUID().uuidString
        let pin2 = UUID().uuidString
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.spkiPinning.pins": .init(.stringArray([pin1, pin2]), isSecret: false)
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        let secureConnection = try #require(resolved.session.configuration.secureConnection)
        #expect(secureConnection.tlsPinningPolicy == .strict)
        #expect(
            secureConnection.tlsPins
                == [pin1, pin2].map {
                    .init(source: .base64String($0), algorithm: SHA256.self)
                }
        )
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func secureConnectionSPKIPinningWithAuditPolicy() async throws {
        // Given
        let pin = UUID().uuidString
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.spkiPinning.pins": .init(.stringArray([pin]), isSecret: false),
                "secureConnection.spkiPinning.policy": "audit",
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        let secureConnection = try #require(resolved.session.configuration.secureConnection)
        #expect(secureConnection.tlsPinningPolicy == .audit)
        #expect(
            secureConnection.tlsPins
                == [.init(source: .base64String(pin), algorithm: SHA256.self)]
        )
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func emptySPKIPinningPinsThrows() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.spkiPinning.pins": .init(.stringArray([]), isSecret: false)
            ])
        )

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
    func invalidSPKIPinningPolicyThrows() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.spkiPinning.pins": .init(
                    .stringArray([UUID().uuidString]),
                    isSecret: false
                ),
                "secureConnection.spkiPinning.policy": "lenient",
            ])
        )

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
    func secureConnectionPrivateKeyWithoutPassword() async throws {
        // Given
        let file = UUID().uuidString
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.privateKey.file": .init(.string(file), isSecret: false),
                "secureConnection.privateKey.format": "der",
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(.init(file, format: .der))
        )
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func secureConnectionPrivateKeyWithPassword() async throws {
        // Given
        let file = UUID().uuidString
        let password = UUID().uuidString
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.privateKey.file": .init(.string(file), isSecret: false),
                "secureConnection.privateKey.password": .init(.string(password), isSecret: true),
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(
                    .init(file, format: .pem, password: NIOSSLSecureBytes(password.utf8))
                )
        )
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func invalidPrivateKeyFormatThrows() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.privateKey.file": "key.p12",
                "secureConnection.privateKey.format": "p12",
            ])
        )

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
    func secureConnectionTLSVersionRange() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.tlsMinimumVersion": "1.2",
                "secureConnection.tlsMaximumVersion": "1.3",
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.secureConnection?.minimumTLSVersion == TLSVersion.v1_2.build())
        #expect(resolved.session.configuration.secureConnection?.maximumTLSVersion == TLSVersion.v1_3.build())
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func secureConnectionMissingKeysContributeNothing() async throws {
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
        #expect(resolved.session.configuration.secureConnection == nil)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func invalidTLSVersionThrows() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "secureConnection.tlsMinimumVersion": "1.4"
            ])
        )

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
    func redirectFollow() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "redirect.mode": "follow",
                "redirect.maxRedirects": 10,
                "redirect.allowCycles": true,
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.redirectConfiguration == .follow(max: 10, allowCycles: true))
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func redirectFollowDefaults() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "redirect.mode": "follow"
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.redirectConfiguration == .follow(max: 5, allowCycles: false))
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func redirectDisallow() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "redirect.mode": "disallow"
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.redirectConfiguration == .disallow)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func redirectMissingModeContributesNothing() async throws {
        // Given
        let reader = ConfigReader(provider: InMemoryProvider(values: [:]))

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.redirectConfiguration == nil)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func invalidRedirectModeThrows() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "redirect.mode": "bounce"
            ])
        )

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
    func maximumConnectionsPerHost() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "maximumConnectionsPerHost": 16
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit == 16)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func maximumConcurrentConnections() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "maximumConcurrentConnections": 4
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.maximumConcurrentConnections == 4)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func connectionLimitsCombined() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "maximumConnectionsPerHost": 16,
                "maximumConcurrentConnections": 4,
            ])
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Configured(reader)
            }
        )

        // Then
        #expect(resolved.session.configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit == 16)
        #expect(resolved.session.configuration.maximumConcurrentConnections == 4)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func scopedReader() async throws {
        // Given
        let reader = ConfigReader(
            provider: InMemoryProvider(values: [
                "myAPI.baseURL": "https://example.com"
            ])
        )

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
