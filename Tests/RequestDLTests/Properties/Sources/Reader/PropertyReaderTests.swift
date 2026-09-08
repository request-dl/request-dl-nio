//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

struct PropertyReaderTests {

    @Test
    func propertyReaderModifiesBasedOnResolvedConfiguration() async throws {
        for _ in 1...5 {
            let content = PropertyGroup {
                BaseURL(.https, host: "apple.com:1090")
                CustomHeader(name: "Authorization", value: UUID().uuidString)
                ReferenceMemoryProperty()
            }

            let resolved = try await resolve(
                TestProperty {
                    PropertyReader(content) { context in
                        if context.requestConfiguration.url.contains("apple.com:1090") {
                            BaseURL(.http, host: "google.com")
                        }

                        if context.requestConfiguration.headers.contains(name: "Authorization") {
                            Authorization(.bearer, token: UUID().uuidString)
                        }
                    }
                }
            )

            #expect(resolved.requestConfiguration.url == "http://google.com?counter=0")
            #expect(
                resolved.requestConfiguration.headers.contains(name: "Authorization") {
                    $0.hasPrefix("Bearer ")
                }
            )

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Checks if the shared property (ReferenceMemoryProperty) also reflects the expected state
        // This also tests the consistency of the counter after multiple PropertyReader executions
        let resolved = try await resolve(ReferenceMemoryProperty())

        // Expects the counter parameter to be present with its initial value '0'
        // This verifies the initial state captured by the first execution of ReferenceMemoryProperty
        #expect(resolved.requestConfiguration.url.contains("counter=0"))
    }

    @Test
    func propertyReader_combinedWithAsyncProperty_resolvesProxyDynamicallyFromComposedURL() async throws {
        // Given
        // Demonstrates that a per-request dynamic proxy (decided from the fully composed URL,
        // with a real `async` lookup in between) doesn't need a dedicated resolver protocol --
        // `PropertyReader` exposes the resolved URL of its `source`, and `AsyncProperty` can
        // `await` before picking the `Proxy` to add as a sibling.
        @Sendable func lookUpProxy(for host: String) async -> (host: String, port: Int)? {
            if host.contains("internal.") {
                return ("internal-proxy.local", 3_128)
            } else if host.contains("external.") {
                return ("external-proxy.local", 8_080)
            } else {
                return nil
            }
        }

        func dynamicProxySession(host: String) -> some Property {
            PropertyReader(BaseURL(.https, host: host)) { context in
                AsyncProperty {
                    if let proxy = await lookUpProxy(for: context.requestConfiguration.url) {
                        Proxy(host: proxy.host, port: proxy.port, connection: .http)
                    }
                }
            }
        }

        // When
        let internalResolved = try await resolve(dynamicProxySession(host: "internal.company.example.com"))
        let externalResolved = try await resolve(dynamicProxySession(host: "external.company.example.com"))
        let unmatchedResolved = try await resolve(dynamicProxySession(host: "other.example.com"))

        // Then
        #expect(internalResolved.requestConfiguration.url == "https://internal.company.example.com")
        #expect(internalResolved.session.configuration.proxy?.host == "internal-proxy.local")
        #expect(internalResolved.session.configuration.proxy?.port == 3_128)

        #expect(externalResolved.session.configuration.proxy?.host == "external-proxy.local")
        #expect(externalResolved.session.configuration.proxy?.port == 8_080)

        #expect(unmatchedResolved.session.configuration.proxy == nil)
    }

    @Test
    func propertyReader_whenCallerWrapsEntireURLTreeAsSource_proxyDecisionSeesFullyComposedURL() async throws {
        // Given
        // `PropertyReader`'s `content` only sees what `source` itself resolved into -- not
        // whatever siblings surround the `PropertyReader` node in the outer tree. A reusable
        // "pick a proxy from the request's URL" component therefore has to have its *caller*
        // wrap the entire URL-producing tree (`BaseURL` + `Path` + `Query`, in whatever order
        // and however many pieces they come in) as `source`, not just a fragment of it.
        func routedRequest<URLTree: Property>(
            @PropertyBuilder urlTree: () -> URLTree
        ) -> some Property {
            PropertyReader(urlTree()) { context in
                if context.requestConfiguration.url.contains("/admin/") {
                    Proxy(host: "admin-proxy.local", port: 3_128, connection: .http)
                } else {
                    Proxy(host: "default-proxy.local", port: 8_080, connection: .http)
                }
            }
        }

        // When
        let adminResolved = try await resolve(
            routedRequest {
                BaseURL(.https, host: "api.example.com")
                Path("admin/users")
                Query(name: "active", value: "true")
            }
        )

        let defaultResolved = try await resolve(
            routedRequest {
                BaseURL(.https, host: "api.example.com")
                Path("public/users")
            }
        )

        // Then
        #expect(adminResolved.requestConfiguration.url == "https://api.example.com/admin/users?active=true")
        #expect(adminResolved.session.configuration.proxy?.host == "admin-proxy.local")

        #expect(defaultResolved.requestConfiguration.url == "https://api.example.com/public/users")
        #expect(defaultResolved.session.configuration.proxy?.host == "default-proxy.local")
    }

    @Test
    func propertyReader_whenURLPartsAreDeclaredOutsideSource_proxyDecisionMissesThem() async throws {
        // Given
        // The gotcha the previous test's contract depends on getting right: `Path` declared as
        // a *sibling* of `PropertyReader` -- not inside its `source` -- never reaches
        // `context.requestConfiguration.url`, even though it still lands in the final request.
        // A caller who only wraps part of the URL tree gets a routing decision made against a
        // stale/partial URL, silently.
        let resolved = try await resolve(
            TestProperty {
                PropertyReader(BaseURL(.https, host: "api.example.com")) { context in
                    if context.requestConfiguration.url.contains("/admin/") {
                        Proxy(host: "admin-proxy.local", port: 3_128, connection: .http)
                    } else {
                        Proxy(host: "default-proxy.local", port: 8_080, connection: .http)
                    }
                }

                Path("admin/users")
            }
        )

        // Then
        // The final request URL does carry `/admin/users`...
        #expect(resolved.requestConfiguration.url == "https://api.example.com/admin/users")
        // ...but the proxy decision, made from `source`'s isolated resolution, never saw it.
        #expect(resolved.session.configuration.proxy?.host == "default-proxy.local")
    }

    @Test func neverBody() async throws {
        // Given
        let property = PropertyReader(EmptyProperty()) { _ in EmptyProperty() }

        // Then
        try await assertNever(property.body)
    }
}

private struct ReferenceMemoryProperty: Property {
    @StoredObject private var object = MemoryReference()

    var body: some Property {
        Query(name: "counter", value: object.counter)
    }
}

private final class MemoryReference: Sendable {

    let counter: Int

    init() {
        counter = ReadCounter.shared.counter
    }
}

private final class ReadCounter: @unchecked Sendable {

    static let shared = ReadCounter()

    var counter: Int {
        lock.withLock {
            let counter = _counter
            _counter += 1
            return counter
        }
    }

    private let lock = Lock()
    private var _counter: Int = .zero
}
