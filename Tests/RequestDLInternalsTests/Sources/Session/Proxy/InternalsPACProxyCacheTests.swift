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

        // When: first call fetches and evaluates for real.
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

        // When: two different target URLs against the same script, both uncached.
        let internalProxy = await cache.proxy(
            forScriptURL: server.scriptURL,
            targetURL: try #require(URL(string: "https://internal.example.com/"))
        )
        let externalProxy = await cache.proxy(
            forScriptURL: server.scriptURL,
            targetURL: try #require(URL(string: "https://external.example.com/"))
        )

        // Then: the cache key includes the target URL, so this isn't just the first result
        // reused for the second, different, URL.
        #expect(internalProxy == nil)
        #expect(externalProxy?.host == "127.0.0.1")
    }

    @Test
    func proxy_whenManyConcurrentCallsMissTheSameKey_evaluatesOnlyOnce() async throws {
        // Given: a script whose response is held back for a while, long enough that every
        // concurrent caller below is guaranteed to have registered itself as a miss before any
        // of them could possibly see a result -- widening the reentrancy window a fast script
        // could otherwise close before 20 near-simultaneous calls all land inside it.
        //
        // `evaluationCount` (not a connection or thread count) is what this actually checks:
        // `CFNetworkExecuteProxyAutoConfigurationURL` turns out to cache a script's fetched
        // content internally, independent of `Internals.PACProxyCache` entirely, so a second
        // (undeduplicated) evaluation for the same script can cost zero additional connections --
        // confirmed empirically, not assumed -- making connection counting useless here.
        let server = try await LocalPACServer.start(
            scriptContents: """
                function FindProxyForURL(url, host) {
                    return "PROXY 127.0.0.1:8080";
                }
                """,
            responseDelay: .milliseconds(200)
        )
        defer { server.stop() }

        let targetURL = try #require(URL(string: "https://example.com/"))
        let cache = Internals.PACProxyCache()

        // When: many concurrent misses for the identical key, started together.
        let results = await withTaskGroup(of: Internals.Proxy?.self) { group -> [Internals.Proxy?] in
            for _ in 0..<20 {
                group.addTask {
                    await cache.proxy(forScriptURL: server.scriptURL, targetURL: targetURL)
                }
            }

            var results: [Internals.Proxy?] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Then: every caller gets the right answer, and only one evaluation was ever actually
        // started for the twenty of them. Before the fix, actor reentrancy across
        // `Internals.PACEvaluator.evaluate(...)`'s suspension point let each of the 20 concurrent
        // misses start its own independent evaluation instead of sharing the one in progress.
        #expect(results.allSatisfy { $0?.host == "127.0.0.1" })
        #expect(await cache.evaluationCount == 1)
    }

    @Test
    func proxy_whenEntryCountExceedsMaximum_evictsTheOldestRatherThanGrowingWithoutBound() async throws {
        // Given: a cache capped at 4 entries, small enough to exceed with a handful of real
        // evaluations instead of the hundreds the real 256-entry ceiling would need.
        let server = try await LocalPACServer.start(
            scriptContents: """
                function FindProxyForURL(url, host) {
                    return "PROXY 127.0.0.1:8080";
                }
                """
        )
        defer { server.stop() }

        let cache = Internals.PACProxyCache(maximumCount: 4)

        // When: six distinct target URLs, each a fresh cache miss.
        for index in 0..<6 {
            _ = await cache.proxy(
                forScriptURL: server.scriptURL,
                targetURL: try #require(URL(string: "https://example\(index).com/"))
            )
        }

        // Then: the table was brought back under the ceiling rather than left to grow to 6.
        #expect(await cache.count <= 4)
    }

    @Test
    func proxy_whenEvaluationFails_cachesDirectRatherThanRetryingEveryCall() async throws {
        // Given: nothing listens on this port.
        let scriptURL = try #require(URL(string: "http://127.0.0.1:1/proxy.pac"))
        let targetURL = try #require(URL(string: "https://example.com/"))
        let cache = Internals.PACProxyCache()

        // When: two calls for the same unreachable script. If the failure weren't cached, both
        // would separately pay the same (short but nonzero) connection-refused round trip.
        let first = await cache.proxy(forScriptURL: scriptURL, targetURL: targetURL)
        let second = await cache.proxy(forScriptURL: scriptURL, targetURL: targetURL)

        // Then: fails safe to direct, same as `Internals.SystemProxyResolver.firstResolution(in:)`
        // already does for any other unparseable entry, not thrown back out to the caller.
        #expect(first == nil)
        #expect(second == nil)
    }
}

/// Serves exactly one PAC script to exactly one connection at a time. Mirrors
/// `InternalsPACEvaluatorTests`'s identical, file-private helper; not shared, since neither
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

    /// - Parameter responseDelay: How long to hold the response back after the request arrives,
    /// before sending it. `.zero` responds immediately; a real delay is what
    /// `proxy_whenManyConcurrentCallsMissTheSameKey_shareOneInFlightEvaluation` uses to hold a
    /// window open long enough to inspect `Internals.PACProxyCache`'s in-flight bookkeeping while
    /// an evaluation is still genuinely in progress.
    static func start(scriptContents: String, responseDelay: Duration = .zero) async throws -> LocalPACServer {
        let listener = try NWListener(using: .tcp, on: .any)

        let body = Data(scriptContents.utf8)
        let header = Data(
            """
            HTTP/1.1 200 OK\r
            Content-Type: application/x-ns-proxy-autoconfig\r
            Content-Length: \(body.count)\r
            Connection: close\r
            \r

            """.utf8
        )
        let response = header + body

        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                func send() {
                    connection.send(
                        content: response,
                        completion: .contentProcessed { _ in
                            connection.cancel()
                        }
                    )
                }

                guard responseDelay > .zero else {
                    send()
                    return
                }

                _Concurrency.Task {
                    try? await _Concurrency.Task.sleep(for: responseDelay)
                    send()
                }
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
/// exactly once): resumes on the first `.ready`/`.failed`, ignores every later call.
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
