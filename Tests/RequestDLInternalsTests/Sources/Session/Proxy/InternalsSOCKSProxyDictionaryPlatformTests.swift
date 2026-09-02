//
// See LICENSE for this package's licensing information.
//

import Testing

#if canImport(Darwin)

import Foundation
import Network
import SwiftAsyncStream

/// Cheap first pass on the open question `Internals.Proxy.buildConnectionProxyDictionary()`'s own
/// doc comment already flags: whether `URLSession` honors `connectionProxyDictionary`'s legacy
/// SOCKS keys (`SOCKSEnable`/`SOCKSProxy`/`SOCKSPort`) *at all*, before committing to building a
/// real SOCKS4/5 server test double to prove a working tunnel end to end. Mirrors
/// `InternalsProxyDictionaryPlatformTests`'s own bare-`NWListener` technique exactly -- a listener
/// standing in for "some process at the configured proxy address," counting connection attempts,
/// nothing that speaks the SOCKS protocol itself -- since that same technique already correctly
/// separated "is the dictionary honored" from "does the resulting tunnel actually carry traffic"
/// for the `.http` keys.
///
/// Uses `https://example.invalid/` as the destination, not a loopback address --
/// `InternalsProxyDictionaryPlatformTests`'s own finding is that every platform bypasses a
/// configured proxy for loopback destinations as OS policy, independent of whether a given key
/// set is honored at all, which would make a loopback destination here prove nothing either way.
///
/// **Finding, confirmed by actually running both tests, not assumed:** `URLSession` does contact
/// the configured SOCKS proxy address -- on macOS and an iOS Simulator alike, and confirmed
/// non-tautological by the negative-control test (no dictionary set, listener never contacted).
/// This overturns the "unreliable/undocumented" framing the original analysis carried forward
/// into excluding `.socks` from `.urlSession` entirely -- at least the connection-attempt half of
/// the picture works. It does **not** yet prove a working SOCKS tunnel end to end (handshake,
/// auth negotiation, address relay) -- only that `URLSession` is willing to dial the configured
/// address, which is the bare minimum a real SOCKS4/5 server test double (this file's own
/// deliberately narrower scope) would need to even get contacted in the first place.
struct InternalsSOCKSProxyDictionaryPlatformTests {

    @Test
    func urlSession_whenSOCKSProxyDictionarySet_contactsConfiguredProxy() async throws {
        // Given / When
        let contacted = try await proxyWasContacted(setProxyDictionary: true)

        // Then
        #expect(contacted)
    }

    /// Negative control for the test above -- without this, a listener that happened to be
    /// contacted for some unrelated reason (a stray system connection, ATS probing, ...) would
    /// make the positive result meaningless. Same discipline `InternalsURLSessionClientCookieTests`
    /// already holds itself to for its own tee assertion.
    @Test
    func urlSession_whenSOCKSProxyDictionaryNotSet_doesNotContactListener() async throws {
        // Given / When
        let contacted = try await proxyWasContacted(setProxyDictionary: false)

        // Then
        #expect(!contacted)
    }

    // MARK: - Private methods

    private func proxyWasContacted(setProxyDictionary: Bool) async throws -> Bool {
        let listener = try NWListener(using: .tcp, on: .any)
        let counter = ConnectAttemptCounter()

        listener.newConnectionHandler = { connection in
            counter.increment()
            connection.cancel()
        }

        let queue = DispatchQueue(label: "InternalsSOCKSProxyDictionaryPlatformTests")

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
        if setProxyDictionary {
            configuration.connectionProxyDictionary = [
                "SOCKSEnable": 1,
                "SOCKSProxy": "127.0.0.1",
                "SOCKSPort": Int(port),
            ]
        }

        let session = URLSession(configuration: configuration)

        // The destination does not need to be reachable, or even resolvable: the only thing under
        // test is whether the proxy gets contacted before (or instead of) any of that.
        _ = try? await session.data(for: URLRequest(url: URL(string: "https://example.invalid/")!))

        // Give a just-missed connection a moment to land -- `data(for:)` returning doesn't
        // guarantee the listener's callback (a separate queue) has already run.
        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

        return counter.count >= 1
    }
}

/// Thread-safe counter, independent of `InternalsProxyDictionaryPlatformTests`'s own private copy
/// so this file stays self-contained.
private final class ConnectAttemptCounter: @unchecked Sendable {

    private let lock = Lock()
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

    private let lock = Lock()
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
