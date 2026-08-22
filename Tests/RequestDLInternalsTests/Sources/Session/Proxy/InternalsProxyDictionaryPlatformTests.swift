//
// See LICENSE for this package's licensing information.
//

import Testing

#if canImport(Darwin)

import Foundation
import Network

/// Cross-platform empirical check of whether `URLSession` honors
/// `URLSessionConfiguration.connectionProxyDictionary`, on whatever Apple platform this test
/// runs on (macOS, and every Simulator/Catalyst destination `xcodebuild test` can target).
///
/// Deliberately independent of `LocalServer`/`LocalHTTPConnectProxy` (NIOSSL-backed, HTTP/1
/// codec) -- those exist to prove a *working tunnel* end to end, which needs the platform's
/// TLS/HTTP stack to cooperate for reasons orthogonal to the question this file asks. This file
/// only asks whether the configured proxy address is contacted **at all**, using a bare
/// `Network.framework` `NWListener` standing in for "some process listening on the configured
/// proxy port."
///
/// **Finding, corrected from an earlier pass in this same investigation:** `connectionProxyDictionary`
/// is *not* broken. The first version of this check pointed at a loopback destination (matching
/// `LocalServer`, which only ever binds to `127.0.0.1`/`localhost`) and saw the proxy never
/// contacted, which was misread as `URLSession` ignoring the dictionary outright. Comparing
/// destinations directly (`127.0.0.1`, `localhost`, an arbitrary non-loopback IP, and a
/// non-resolving hostname), across macOS, Mac Catalyst, and iOS/tvOS/watchOS/visionOS Simulators,
/// isolated the real cause -- and a second, narrower one underneath it:
///
/// - Every platform bypasses a configured proxy for the **literal** loopback IP
///   (`127.0.0.1`) as OS-level policy, independent of this dictionary being wired correctly.
/// - **macOS and Mac Catalyst additionally bypass `localhost` by name.** iOS, tvOS, watchOS, and
///   visionOS Simulators do **not** -- `localhost` gets proxied there exactly like any other
///   hostname. (Simulators share their host Mac's network stack for the underlying socket, but
///   evidently not this particular CFNetwork policy decision -- Catalyst, which really does run
///   the macOS frameworks directly, matches macOS exactly, which is what makes this a platform
///   distinction and not a "shares the same kernel" artifact.)
/// - Non-loopback destinations are proxied reliably everywhere.
///
/// `InternalsURLSessionClientProxyTests` (which uses `LocalServer`, always `localhost`) keeps the
/// macOS/Catalyst-specific finding as a conditional `withKnownIssue`; this file is the actual
/// proof the mapping itself works, and the precise per-platform matrix for `localhost`.
struct InternalsProxyDictionaryPlatformTests {

    @Test
    func urlSession_whenConnectionProxyDictionarySet_contactsConfiguredProxyForNonLoopbackTarget() async throws {
        // Given / When
        let contacted = try await proxyWasContacted(destination: "https://example.invalid/")

        // Then
        #expect(contacted)
    }

    @Test
    func urlSession_whenConnectionProxyDictionarySet_bypassesProxyForLiteralLoopbackIP() async throws {
        // Given / When -- unlike `localhost` below, contacting `127.0.0.1` directly is bypassed
        // on every platform this was checked on.
        let contacted = try await proxyWasContacted(destination: "https://127.0.0.1:9/")

        // Then
        #expect(!contacted)
    }

    @Test
    func urlSession_whenConnectionProxyDictionarySet_localhostBehaviorMatchesPlatformMatrix() async throws {
        // Given / When
        let contacted = try await proxyWasContacted(destination: "https://localhost:9/")

        // Then -- see the file-level doc comment for why this genuinely differs by platform
        // rather than being flaky: macOS/Catalyst bypass `localhost` same as the literal IP;
        // every Simulator platform proxies it like any other hostname.
        #if os(macOS) || targetEnvironment(macCatalyst)
        #expect(!contacted)
        #else
        #expect(contacted)
        #endif
    }

    // MARK: - Private methods

    private func proxyWasContacted(destination: String) async throws -> Bool {
        let listener = try NWListener(using: .tcp, on: .any)
        let counter = ConnectAttemptCounter()

        listener.newConnectionHandler = { connection in
            counter.increment()
            connection.cancel()
        }

        let queue = DispatchQueue(label: "InternalsProxyDictionaryPlatformTests")

        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let box = ContinuationBox(continuation)

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

        defer { listener.cancel() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": Int(port),
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": Int(port),
        ]

        let session = URLSession(configuration: configuration)

        // The destination does not need to be reachable, or even resolvable: the only thing
        // under test is whether the proxy gets contacted before (or instead of) any of that,
        // which happens at `CONNECT`/connection-establishment time, before the destination is
        // ever touched.
        _ = try? await session.data(for: URLRequest(url: URL(string: destination)!))

        // Give a just-missed connection a moment to land -- `data(for:)` returning doesn't
        // guarantee the listener's callback (a separate queue) has already run.
        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

        return counter.count >= 1
    }
}

/// Thread-safe counter, independent of `LocalHTTPConnectProxy.ConnectAttemptCounter`
/// (`RequestDLTestSupport`, not a dependency of this target) so this file stays self-contained.
private final class ConnectAttemptCounter: @unchecked Sendable {

    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }
}

/// Bridges `NWListener.stateUpdateHandler` (called repeatedly) to a `CheckedContinuation` (usable
/// exactly once) -- resumes on the first `.ready`/`.failed`, ignores every later call.
private final class ContinuationBox: @unchecked Sendable {

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
        let continuation = self.continuation
        self.continuation = nil
        return continuation
    }
}

private struct MissingListenerPortError: Error {}

#endif
