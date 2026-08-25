//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

/// Phase 7b3 of `URLSESSION_TASK.md`: `RawTask.result()` dispatches through
/// `Internals.Session.resolvedClient()` (backed by `Internals.ClientManager.shared`, the same
/// pool every real request in the process shares) instead of the NIO-only `client()`, so
/// `preferredExecutor`/`requiredExecutor` finally decide which backend a real `DataTask` runs
/// over -- closing the gap Phase 7a's own acceptance section flagged: pinning or preferring
/// `.urlSession` validated and threw correctly, but never actually routed a real request there.
///
/// `InternalsClientManagerExecutorTests` (`RequestDLInternalsTests`) already proved
/// `Internals.ClientManager.resolvedClient(provider:sessionConfiguration:)` resolves and caches a
/// working `.urlSession` client, using a hand-built `Internals.ClientManager`/`SessionProvider` --
/// deliberately isolated from the `Property`/`Resolve` pipeline and from `Internals.ClientManager
/// .shared`. This file proves the layer above that: a real `DataTask`, resolved through an actual
/// `Property` tree exactly as an app would build one, and dispatched via the *same* shared pool
/// `RawTask.result()` itself reads from -- not a fresh, test-isolated manager.
struct RawTaskExecutorDispatchTests {

    @Test
    func dataTask_whenNoExecutorPreferenceSet_actuallyDispatchesOverURLSessionOnDarwin() async throws {
        // Given -- a config compatible with every executor, so `.urlSession` is
        // `resolveExecutor()`'s own default preference (Phase 3), not something forced here. A
        // session id unique to this test run keeps it off `Session.localServer`'s shared pooled
        // entry, so nothing else running concurrently can affect (or be affected by) the
        // `Internals.ClientManager.shared` lookup below.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let content = TestProperty {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.7b3-dispatch.\(UUID())")

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }

        // When -- through the real public API, exactly as an app would call it. No executor
        // modifier anywhere in `content` above.
        let data = try await DataTask { content }.extractPayload().result()

        let result = try HTTPResult<String>(data)
        #expect(result.response == output)

        // Then -- resolving the identical property tree again and asking
        // `Internals.ClientManager.shared` (the pool the `DataTask` call above actually used)
        // what it holds for this exact provider is what proves the *real* call dispatched over
        // `.urlSession`, rather than merely that `.urlSession` was resolvable in isolation.
        let resolved = try await resolve(content)

        guard case .urlSession = try await resolved.session.resolvedClient() else {
            Issue.record("Expected the DataTask call above to have dispatched over .urlSession")
            return
        }
    }

    @Test
    func dataTask_whenNIORequired_actuallyDispatchesOverNIOEvenThoughURLSessionWouldBeCompatible() async throws {
        // Given -- same shape as above (would default to `.urlSession` on Darwin), but this time
        // pinned to `.nio` explicitly. Regression coverage for the bug this phase's own testing
        // caught: `requiredExecutor(.nio)` used to validate without ever actually being the
        // executor a real request dispatched over -- `resolveExecutor()` read only
        // `preferredExecutor`, so a `.urlSession`-compatible config kept resolving there anyway.
        // See `InternalsSessionConfigurationExecutorTests`'s "resolveExecutor() with
        // requiredExecutor" section for the unit-level fix; this is the same fact proven one
        // layer up, through a real `DataTask` round trip.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let content = TestProperty {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.7b3-dispatch.\(UUID())")
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }

        // When
        let data = try await DataTask { content }.extractPayload().result()

        let result = try HTTPResult<String>(data)
        #expect(result.response == output)

        // Then
        let resolved = try await resolve(content)

        guard case .nio = try await resolved.session.resolvedClient() else {
            Issue.record("Expected the DataTask call above to have dispatched over .nio")
            return
        }
    }
}

#endif
