//
// See LICENSE for this package's licensing information.
//

import Configuration
import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL

/// `Configured` reads bearer tokens, Basic passwords and credentials, proxy credentials and the
/// header lists as secrets, because swift-configuration's access loggers redact only what is
/// marked secret.
struct ConfiguredSecretsTests {

    /// Which keys were read, and whether each was reported as secret.
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    private final class Recorder: AccessReporter, @unchecked Sendable {

        private let lock = Lock()
        private var flags: [String: Bool] = [:]

        func report(_ event: AccessEvent) {
            let key = event.metadata.key.description
            let isSecret = (try? event.result.get())?.isSecret ?? false

            lock.withLock { flags[key] = (flags[key] ?? false) || isSecret }
        }

        func isSecret(_ key: String) -> Bool? {
            lock.withLock { flags[key] }
        }
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    private func read(_ values: [AbsoluteConfigKey: ConfigValue]) async throws -> Recorder {
        let recorder = Recorder()
        let reader = ConfigReader(provider: InMemoryProvider(values: values), accessReporter: recorder)

        _ = try await resolve(TestProperty { Configured(reader) })

        return recorder
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func credentials_arePassedAsSecrets_forBasicAndBearerAndProxy() async throws {
        // Given: Basic user and password, a proxy that uses a bearer token, and the lists of
        // headers that can carry an Authorization or an API key.
        let first = try await read([
            "authorization.scheme": "basic",
            "authorization.username": "user",
            "authorization.password": "hunter2",
            "headers": .init(.stringArray(["X-API-Key: abc"]), isSecret: false),
            "queries": .init(.stringArray(["api_key=abc"]), isSecret: false),
            "proxy.enabled": true,
            "proxy.host": "proxy.example.com",
            "proxy.port": 8_080,
            "proxy.authorization.scheme": "bearer",
            "proxy.authorization.token": "proxy-token",
            "proxy.connectHeaders": .init(.stringArray(["Proxy-Authorization: Bearer x"]), isSecret: false),
        ])

        // And: pre-encoded Basic credentials, a bearer token, and a proxy with Basic.
        let second = try await read([
            "authorization.scheme": "basic",
            "authorization.credentials": "dXNlcjpwYXNz",
            "proxy.enabled": true,
            "proxy.host": "proxy.example.com",
            "proxy.port": 8_080,
            "proxy.authorization.scheme": "basic",
            "proxy.authorization.username": "user",
            "proxy.authorization.password": "hunter2",
        ])

        let third = try await read([
            "authorization.scheme": "bearer",
            "authorization.token": "token",
            "proxy.enabled": true,
            "proxy.host": "proxy.example.com",
            "proxy.port": 8_080,
            "proxy.authorization.scheme": "basic",
            "proxy.authorization.credentials": "dXNlcjpwYXNz",
        ])

        // Then
        #expect(first.isSecret("authorization.password") == true)
        #expect(first.isSecret("headers") == true)
        #expect(first.isSecret("queries") == true)
        #expect(first.isSecret("proxy.authorization.token") == true)
        #expect(first.isSecret("proxy.connectHeaders") == true)

        #expect(second.isSecret("authorization.credentials") == true)
        #expect(second.isSecret("proxy.authorization.password") == true)

        #expect(third.isSecret("authorization.token") == true)
        #expect(third.isSecret("proxy.authorization.credentials") == true)
    }

    /// Marking everything secret would make the access logs useless; what is not a credential
    /// stays readable.
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func nonSecretKeys_staySerialisedInTheClear() async throws {
        let recorder = try await read([
            "baseURL": "https://example.com",
            "method": "post",
            "timeout": 30,
            "authorization.scheme": "basic",
            "authorization.username": "user",
            "authorization.password": "hunter2",
        ])

        #expect(recorder.isSecret("baseURL") == false)
        #expect(recorder.isSecret("method") == false)
        #expect(recorder.isSecret("timeout") == false)
        #expect(recorder.isSecret("authorization.scheme") == false)
        #expect(recorder.isSecret("authorization.username") == false)
    }
}
