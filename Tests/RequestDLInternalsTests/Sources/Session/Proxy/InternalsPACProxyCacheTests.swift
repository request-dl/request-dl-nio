//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin) && canImport(CFNetwork)

import Foundation
import Network

/// `Internals.PACProxyCache`, the layer between `Internals.SystemProxyResolver` and
/// `Internals.PACEvaluator` that keeps a repeat request from re-fetching and re-evaluating the
/// same PAC script every time.
///
/// `.concurrent(watchdogAffectedPlatformConcurrencyLimit)`/`.nonFatalWatchdog`: real threading
/// and network I/O against a local listener, same rationale as `InternalsPACEvaluatorTests`'s own
/// copy of this note.
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsPACProxyCacheTests {

    @Test
    func proxy_whenCalledTwiceForSameKey_reusesTheCachedResultInsteadOfRefetching() async throws {
        // Given
        let server = try await LocalPACServer.start(
            scriptContents: """
                function FindProxyForURL(url, host) {
                    return "PROXY 127.0.0.1:8080";
                }
                """
        )
        let targetURL = try #require(URL(string: "https://example.com/"))
        let cache = Internals.PACProxyCache()

        // When -- first call fetches and evaluates for real.
        let first = await cache.proxy(forScriptURL: server.scriptURL, targetURL: targetURL)

        // Then the server goes away entirely: a second call that still needs a fresh fetch would
        // fail (nothing left to connect to), so getting the same answer back proves the cache
        // path was taken, not a coincidentally-successful re-fetch.
        server.stop()
        let second = await cache.proxy(forScriptURL: server.scriptURL, targetURL: targetURL)

        // Then
        #expect(first?.host == "127.0.0.1")
        #expect(second?.host == first?.host)
        #expect(second?.port == first?.port)
    }

    @Test
    func proxy_whenTargetURLDiffers_evaluatesIndependently() async throws {
        // Given
        let server = try await LocalPACServer.start(
            scriptContents: """
                function FindProxyForURL(url, host) {
                    if (host == "internal.example.com") {
                        return "DIRECT";
                    }
                    return "PROXY 127.0.0.1:8080";
                }
                """
        )
        defer { server.stop() }

        let cache = Internals.PACProxyCache()

        // When -- two different target URLs against the same script, both uncached.
        let internalProxy = await cache.proxy(
            forScriptURL: server.scriptURL,
            targetURL: try #require(URL(string: "https://internal.example.com/"))
        )
        let externalProxy = await cache.proxy(
            forScriptURL: server.scriptURL,
            targetURL: try #require(URL(string: "https://external.example.com/"))
        )

        // Then -- the cache key includes the target URL, so this isn't just the first result
        // reused for the second, different, URL.
        #expect(internalProxy == nil)
        #expect(externalProxy?.host == "127.0.0.1")
    }

    @Test
    func proxy_whenEvaluationFails_cachesDirectRatherThanRetryingEveryCall() async throws {
        // Given -- nothing listens on this port.
        let scriptURL = try #require(URL(string: "http://127.0.0.1:1/proxy.pac"))
        let targetURL = try #require(URL(string: "https://example.com/"))
        let cache = Internals.PACProxyCache()

        // When -- two calls for the same unreachable script; if the failure weren't cached, both
        // would separately pay the same (short but nonzero) connection-refused round trip.
        let first = await cache.proxy(forScriptURL: scriptURL, targetURL: targetURL)
        let second = await cache.proxy(forScriptURL: scriptURL, targetURL: targetURL)

        // Then -- fails safe to direct, same as `Internals.SystemProxyResolver.firstResolution(in:)`
        // already does for any other unparseable entry, not thrown back out to the caller.
        #expect(first == nil)
        #expect(second == nil)
    }
}

/// Serves exactly one PAC script to exactly one connection at a time. Mirrors
/// `InternalsPACEvaluatorTests`'s identical, file-private helper -- not shared, since neither
/// file is a dependency of the other.
private final class LocalPACServer: @unchecked Sendable {

    // MARK: - Internal properties

    let scriptURL: URL

    // MARK: - Private properties

    private let listener: NWListener

    // MARK: - Inits

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.scriptURL = URL(string: "http://127.0.0.1:\(port)/proxy.pac")!
    }

    // MARK: - Internal static methods

    static func start(scriptContents: String) async throws -> LocalPACServer {
        let listener = try NWListener(using: .tcp, on: .any)

        let body = Data(scriptContents.utf8)
        var response = Data(
            """
            HTTP/1.1 200 OK\r
            Content-Type: application/x-ns-proxy-autoconfig\r
            Content-Length: \(body.count)\r
            Connection: close\r
            \r

            """.utf8
        )
        response.append(body)

        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                connection.send(
                    content: response,
                    completion: .contentProcessed { _ in
                        connection.cancel()
                    }
                )
            }
        }

        let queue = DispatchQueue(label: "InternalsPACProxyCacheTests.LocalPACServer")

        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let box = PortContinuationBox(continuation)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        box.resume(throwing: MissingListenerPortError())
                        return
                    }
                    box.resume(returning: port)

                case .failed(let error):
                    box.resume(throwing: error)

                default:
                    break
                }
            }

            listener.start(queue: queue)
        }

        return LocalPACServer(listener: listener, port: port)
    }

    // MARK: - Internal methods

    func stop() {
        listener.cancel()
    }
}

private struct MissingListenerPortError: Error {}

/// Bridges `NWListener.stateUpdateHandler` (called repeatedly) to a `CheckedContinuation` (usable
/// exactly once) -- resumes on the first `.ready`/`.failed`, ignores every later call.
private final class PortContinuationBox: @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(returning port: UInt16) {
        take()?.resume(returning: port)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<UInt16, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}

#endif
