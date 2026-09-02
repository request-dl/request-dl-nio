//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(Darwin)

struct InternalsProxyURLSessionTests {

    @Test
    func buildConnectionProxyDictionary_whenHTTP_setsHTTPAndHTTPSKeys() async throws {
        // Given
        let proxy = Internals.Proxy(
            host: "proxy.example.com",
            port: 8080,
            connection: .http,
            authorization: nil
        )

        // When
        let dictionary = proxy.buildConnectionProxyDictionary()

        // Then
        #expect(dictionary["HTTPEnable"] as? Int == 1)
        #expect(dictionary["HTTPProxy"] as? String == "proxy.example.com")
        #expect(dictionary["HTTPPort"] as? Int == 8080)
        #expect(dictionary["HTTPSEnable"] as? Int == 1)
        #expect(dictionary["HTTPSProxy"] as? String == "proxy.example.com")
        #expect(dictionary["HTTPSPort"] as? Int == 8080)
    }

    @Test
    func buildConnectionProxyDictionary_whenSOCKS_setsSOCKSKeys() async throws {
        // Given
        let proxy = Internals.Proxy(
            host: "proxy.example.com",
            port: 1080,
            connection: .socks,
            authorization: nil
        )

        // When
        let dictionary = proxy.buildConnectionProxyDictionary()

        // Then
        #expect(dictionary["SOCKSEnable"] as? Int == 1)
        #expect(dictionary["SOCKSProxy"] as? String == "proxy.example.com")
        #expect(dictionary["SOCKSPort"] as? Int == 1080)
        // No `HTTP*`/`HTTPS*` keys leak in from the other branch.
        #expect(dictionary["HTTPEnable"] == nil)
    }
}

#endif
