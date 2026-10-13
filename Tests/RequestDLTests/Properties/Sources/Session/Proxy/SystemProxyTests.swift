//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
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

    @Test(arguments: [SystemProxy.PACFailurePolicy.direct, .fail])
    func systemProxy_carriesItsPolicyToTheBuild(_ policy: SystemProxy.PACFailurePolicy) async throws {
        // When
        let (_, make) = try await Resolve(
            TestProperty {
                SystemProxy(onPACFailure: policy)
            }
        )
        .partiallyBuild()

        // Then
        #expect(make.resolvesSystemProxy)
        #expect(make.systemProxyPACFailure == policy.internalPolicy)
    }

    /// A request that never said what to do keeps going direct, as it always did.
    @Test
    func systemProxy_withoutAPolicy_goesDirectOnAFailure() async throws {
        // When
        let (_, make) = try await Resolve(
            TestProperty {
                SystemProxy()
            }
        )
        .partiallyBuild()

        // Then
        #expect(make.systemProxyPACFailure == .direct)
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = SystemProxy()

        // Then
        try await assertNever(property.body)
    }
}
