//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import class Foundation.ProcessInfo
#endif

struct UserAgentHeaderTests {

    @Test
    func agent_whenNoValueIsSet() async throws {
        // Given
        let property = TestProperty(EmptyProperty())

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(resolved.requestConfiguration.headers["User-Agent"] == nil)
    }

    @Test
    func agent_whenValueIsSetWithAddStrategy() async throws {
        // Given
        let userAgent = "A text agent specification"

        // When
        let resolved = try await resolve(
            TestProperty {
                UserAgentHeader(userAgent)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["User-Agent"] == [userAgent])
    }

    @Test
    func agent_whenUsingDefaultValue() async throws {
        // Given
        let property = TestProperty {
            UserAgentHeader()
        }

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(resolved.requestConfiguration.headers["User-Agent"] == [ProcessInfo.processInfo.userAgent])
    }

    @Test
    func agent_whenUsingDefaultValueWithCustomAgent() async throws {
        // Given
        let userAgent = "CustomAgent"
        // When
        let resolved = try await resolve(
            TestProperty {
                HeaderGroup {
                    UserAgentHeader()
                    UserAgentHeader(userAgent)
                }
                .headerStrategy(.adding)
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.headers["User-Agent"] == [
                ProcessInfo.processInfo.userAgent + " \(userAgent)"
            ]
        )
    }

    @Test
    func hasDefaultUserAgent_whenUsingDefaultValue() async throws {
        // Given
        let property = TestProperty {
            UserAgentHeader()
        }

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(resolved.requestConfiguration.hasDefaultUserAgent)
    }

    @Test
    func hasDefaultUserAgent_whenValueIsCustom() async throws {
        // Given
        let property = TestProperty {
            UserAgentHeader("CustomAgent")
        }

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(!resolved.requestConfiguration.hasDefaultUserAgent)
    }

    @Test
    func hasDefaultUserAgent_whenNoValueIsSet() async throws {
        // Given
        let property = TestProperty(EmptyProperty())

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(!resolved.requestConfiguration.hasDefaultUserAgent)
    }

    @Test
    func hasDefaultUserAgent_whenDefaultIsCombinedWithCustomAgent() async throws {
        // Given
        let userAgent = "CustomAgent"

        // When
        let resolved = try await resolve(
            TestProperty {
                HeaderGroup {
                    UserAgentHeader()
                    UserAgentHeader(userAgent)
                }
                .headerStrategy(.adding)
            }
        )

        // Then -- once a custom value is folded in too, the header is no longer purely
        // RequestDL's untouched default, so it must not be reported as such.
        #expect(!resolved.requestConfiguration.hasDefaultUserAgent)
    }

    @Test
    func dropDefaultUserAgentForNativeReporting_removesOnlyTheUntouchedDefault() async throws {
        // Given
        var withDefault = try await resolve(
            TestProperty { UserAgentHeader() }
        ).requestConfiguration

        var withCustom = try await resolve(
            TestProperty { UserAgentHeader("CustomAgent") }
        ).requestConfiguration

        // When
        withDefault.dropDefaultUserAgentForNativeReporting()
        withCustom.dropDefaultUserAgentForNativeReporting()

        // Then -- URLSession synthesizes its own accurate User-Agent only when the request
        // carries none, so the untouched default is removed to let it do that, while a value
        // the caller actually asked for must reach the wire untouched.
        #expect(withDefault.headers["User-Agent"] == nil)
        #expect(withCustom.headers["User-Agent"] == ["CustomAgent"])
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = UserAgentHeader("CustomAgent/1.0.0")

        // Then
        try await assertNever(property.body)
    }
}
