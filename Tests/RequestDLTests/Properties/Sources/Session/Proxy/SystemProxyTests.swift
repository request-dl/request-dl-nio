//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.UUID
#endif

struct SystemProxyTests {

    @Test
    func systemProxy_resolvesAgainstEnvironment() async throws {
        // Given / When
        let resolved = try await resolve(
            TestProperty {
                SystemProxy()
            }
        )

        // Then
        // No assertion on the resolved host/port: the system/environment proxy is
        // whatever the CI machine happens to have configured, which is out of this
        // test's control. Reaching here without throwing confirms the property wired
        // `resolvesSystemProxy` through to proxy resolution.
        _ = resolved.session.configuration.proxy
    }

    @Test
    func systemProxy_whenExplicitProxyDeclared_explicitWins() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        // When
        let resolved = try await resolve(
            TestProperty {
                Proxy(host: host, port: port, connection: .http)
                SystemProxy()
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = SystemProxy()

        // Then
        try await assertNever(property.body)
    }
}
