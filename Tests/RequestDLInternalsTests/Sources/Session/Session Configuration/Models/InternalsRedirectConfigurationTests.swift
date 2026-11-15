//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

// Only the two `.build()` tests below need AsyncHTTPClient; `Internals.RedirectConfiguration
// .build()` only exists under `canImport(NIOCore)` (it returns `HTTPClient.Configuration
// .RedirectConfiguration`).
#if canImport(NIOCore)
import AsyncHTTPClient
#endif

struct InternalsRedirectConfigurationTests {

    #if canImport(NIOCore)
    @Test
    func redirect_whenDisallow() {
        // Given
        let redirect = Internals.RedirectConfiguration.disallow

        // When
        let sut = redirect.build()

        // Then
        #expect(
            String(describing: sut)
                == String(
                    describing: HTTPClient.Configuration.RedirectConfiguration.disallow
                )
        )
    }

    /// Not AsyncHTTPClient's own `.follow(max:allowCycles:)`, which replays an explicit `Host` on a
    /// redirect to another origin and has no hook to stop it: the same limits, as a strategy. See
    /// `Internals.NIOFollowRedirectStrategy`.
    @Test
    func redirect_whenFollow_buildsTheFollowStrategy() {
        // Given
        let redirect = Internals.RedirectConfiguration.follow(max: 1_024, allowCycles: true)

        // When
        let sut = redirect.build()

        // Then: `mode` is internal to AsyncHTTPClient, so, as above, what it prints is what is compared.
        let description = String(describing: sut)
        #expect(description.contains("NIOFollowRedirectStrategy"))
        #expect(description.contains("max: 1024"))
        #expect(description.contains("allowCycles: true"))
    }
    #endif

    @Test
    func redirect_whenEquals() {
        // Given
        let lhs = Internals.RedirectConfiguration.disallow
        let rhs = Internals.RedirectConfiguration.disallow

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func redirect_whenNotEquals() {
        // Given
        let lhs = Internals.RedirectConfiguration.disallow
        let rhs = Internals.RedirectConfiguration.follow(max: 1_024, allowCycles: true)

        // Then
        #expect(lhs != rhs)
    }
}
