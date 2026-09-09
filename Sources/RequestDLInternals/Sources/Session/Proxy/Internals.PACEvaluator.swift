//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin) && canImport(CFNetwork)

import CFNetwork
import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import class Foundation.Thread
import struct Foundation.URL
#endif

extension Internals {

    /// Bridges `CFNetworkExecuteProxyAutoConfigurationURL` -- a callback/`CFRunLoopSource` API,
    /// not `async`-native -- into `async throws`.
    ///
    /// The Swift Concurrency cooperative thread pool never runs a `CFRunLoop` on any of its
    /// threads (nothing calls `CFRunLoopRun()`/`CFRunLoopRunInMode()` there), so simply adding
    /// the source CFNetwork hands back to "the current run loop" from a `Task` would leave it
    /// registered but never pumped -- the callback would never fire, and the awaiting
    /// continuation would hang forever. This spins one dedicated, short-lived `Thread` per
    /// evaluation instead, whose only job is to add the source to its own run loop and pump that
    /// loop (`CFRunLoopRunInMode`) until either the callback fires or `timeout` elapses.
    ///
    /// One thread per call, not a shared long-lived one: PAC evaluation is a rare, slow
    /// (network-fetch-bound), cached operation (see `Internals.PACProxyCache`) -- the cost of
    /// spinning a thread per *uncached* call is negligible next to the fetch itself, and it
    /// avoids the lifecycle/reentrancy bookkeeping a shared pumped run loop would need for
    /// concurrent callers.
    package enum PACEvaluator {

        /// Why `evaluate(scriptURL:targetURL:timeout:)` didn't produce a proxy list.
        package enum Error: Swift.Error, Sendable {
            /// The script's fetch and evaluation didn't finish within `timeout`.
            case timedOut
            /// The script fetched, but failed to parse or evaluate as JavaScript, threw, or the
            /// input was malformed enough that `CFNetworkExecuteProxyAutoConfigurationURL` itself
            /// reported failure through `pacEvaluationCallback`'s `error` rather than by starting
            /// at all.
            case executionFailed(String)
        }

        /// Fetches `scriptURL`'s contents, evaluates it as a PAC script against `targetURL`, and
        /// returns the first directly-usable proxy the script resolves to (`nil` for an explicit
        /// direct connection, or for a script that resolves to nothing this package recognizes).
        ///
        /// Parsed via `Internals.SystemProxyResolver.firstUsableProxy(in:)` -- the exact same
        /// dictionary-shape parsing the non-PAC path already does, since
        /// `CFNetworkExecuteProxyAutoConfigurationURL`'s result uses the identical shape
        /// `CFNetworkCopyProxiesForURL` does (minus any `kCFProxyTypeAutoConfigurationURL` entry --
        /// CFNetwork's own guarantee that a script cannot chain to another PAC file). Parsed
        /// inside `pacEvaluationCallback`, before the result ever crosses back into `async`
        /// context: the raw `CFArray` of `[String: Any]` dictionaries isn't `Sendable`, but the
        /// parsed `Internals.Proxy?` is.
        package static func evaluate(
            scriptURL: URL,
            targetURL: URL,
            timeout: Double
        ) async throws -> Internals.Proxy? {
            try await withCheckedThrowingContinuation { continuation in
                let box = PACContinuationBox(continuation)

                let thread = Thread {
                    box.run(scriptURL: scriptURL, targetURL: targetURL, timeout: timeout)
                }
                thread.name = "RequestDL.PACEvaluator"
                thread.stackSize = 256 * 1_024
                thread.start()
            }
        }
    }
}

/// Owns exactly one `evaluate(...)` call's continuation, the run loop that pumps it, and the
/// `CFRunLoopSource` CFNetwork hands back -- one instance per call, never shared, never reused.
private final class PACContinuationBox: @unchecked Sendable {

    // MARK: - Private properties

    private let lock = Lock()
    private var isResumed = false
    private let continuation: CheckedContinuation<Internals.Proxy?, Swift.Error>

    // MARK: - Inits

    init(_ continuation: CheckedContinuation<Internals.Proxy?, Swift.Error>) {
        self.continuation = continuation
    }

    // MARK: - Internal methods

    /// Runs entirely on the dedicated thread `PACEvaluator.evaluate(...)` spun up for it --
    /// blocks that thread (and only that thread) until `resume(returning:)`/`resume(throwing:)`
    /// has been called exactly once, one way or another.
    func run(scriptURL: URL, targetURL: URL, timeout: Double) {
        let runLoop = CFRunLoopGetCurrent()

        var context = CFStreamClientContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let source = CFNetworkExecuteProxyAutoConfigurationURL(
            scriptURL as CFURL,
            targetURL as CFURL,
            pacEvaluationCallback,
            &context
        )

        CFRunLoopAddSource(runLoop, source, .defaultMode)
        defer { CFRunLoopRemoveSource(runLoop, source, .defaultMode) }

        // `false`: only `CFRunLoopStop(_:)` (fired by `pacEvaluationCallback` below, the instant
        // the result is in) or `timeout` elapsing ends this -- not merely the first source this
        // run loop happens to service, which need not be the PAC one.
        let result = CFRunLoopRunInMode(.defaultMode, timeout, false)

        if result == .timedOut {
            resume(throwing: Internals.PACEvaluator.Error.timedOut)
        }
    }

    func resume(returning proxy: Internals.Proxy?) {
        lock.withLock {
            guard !isResumed else { return }
            isResumed = true
            continuation.resume(returning: proxy)
        }
    }

    func resume(throwing error: Swift.Error) {
        lock.withLock {
            guard !isResumed else { return }
            isResumed = true
            continuation.resume(throwing: error)
        }
    }
}

/// `@convention(c)`, so it cannot capture anything -- `info` (round-tripped through
/// `CFStreamClientContext` unretained, since the box already outlives the call by blocking its
/// own thread in `CFRunLoopRunInMode` for exactly this long) is how `PACContinuationBox.run(...)`
/// hands this its identity back.
private func pacEvaluationCallback(
    _ info: UnsafeMutableRawPointer,
    _ proxyList: CFArray,
    _ error: CFError?
) {
    defer { CFRunLoopStop(CFRunLoopGetCurrent()) }

    let box = Unmanaged<PACContinuationBox>.fromOpaque(info).takeUnretainedValue()

    if let error {
        box.resume(throwing: Internals.PACEvaluator.Error.executionFailed(String(describing: error)))
    } else {
        let proxies = (proxyList as? [[String: Any]]) ?? []
        box.resume(returning: Internals.SystemProxyResolver.firstUsableProxy(in: proxies))
    }
}

#endif
