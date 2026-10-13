//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin) && canImport(CFNetwork)

import Foundation

/// What `Internals.PACProxyCache` asks the evaluator and how many evaluations it lets run at
/// once, against a stand-in evaluator, so neither depends on a real PAC server or on timing.
struct InternalsPACProxyCacheKeyTests {

    private static let scriptURL = URL(string: "http://127.0.0.1:1/proxy.pac")!

    private static func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    // MARK: - The target a script is asked about

    /// The cache is keyed by origin for secure targets, so requests that differ only in their
    /// query (pagination, signed URLs) share one thread and one script run.
    @Test
    func proxy_whenSecureTargetsDifferOnlyInPathOrQuery_evaluatesOnceForTheOrigin() async throws {
        // Given
        let evaluations = Evaluations()
        let cache = Internals.PACProxyCache(evaluate: evaluations.evaluator)

        // When
        for target in [
            "https://example.com/items?page=1",
            "https://example.com/items?page=2",
            "https://example.com/other/path#section",
            "https://user:secret@example.com/",
        ] {
            _ = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: try Self.url(target))
        }

        // Then: one evaluation, and the script never saw a path, query or credentials.
        #expect(await cache.evaluationCount == 1)
        #expect(await evaluations.targets == [try Self.url("https://example.com/")])
    }

    @Test
    func proxy_whenSecureTargetsDifferInHostCaseOnly_evaluatesOnce() async throws {
        // Given
        let evaluations = Evaluations()
        let cache = Internals.PACProxyCache(evaluate: evaluations.evaluator)

        // When
        _ = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: try Self.url("https://Example.COM/a"))
        _ = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: try Self.url("https://example.com/b"))

        // Then
        #expect(await cache.evaluationCount == 1)
    }

    @Test
    func proxy_whenSecureTargetsDifferInPortOrHost_evaluatesEach() async throws {
        // Given
        let evaluations = Evaluations()
        let cache = Internals.PACProxyCache(evaluate: evaluations.evaluator)

        // When
        for target in ["https://example.com/", "https://example.com:8443/", "https://other.example.com/"] {
            _ = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: try Self.url(target))
        }

        // Then
        #expect(await cache.evaluationCount == 3)
        #expect(await evaluations.targets.contains(try Self.url("https://example.com:8443/")))
    }

    /// A script may route plain `http` on its path (browsers hand it the whole URL), so those
    /// keep their full address.
    @Test
    func proxy_whenInsecureTargetsDifferInPathOrQuery_evaluatesEachWithTheFullAddress() async throws {
        // Given
        let evaluations = Evaluations()
        let cache = Internals.PACProxyCache(evaluate: evaluations.evaluator)

        let first = try Self.url("http://example.com/api/items?page=1")
        let second = try Self.url("http://example.com/static/logo.png")

        // When
        _ = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: first)
        _ = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: second)

        // Then
        #expect(await cache.evaluationCount == 2)
        #expect(await evaluations.targets == [first, second])
    }

    // MARK: - How many evaluations run at once

    /// Cache misses do not each start a dedicated thread without a ceiling.
    @Test
    func proxy_whenManyDistinctTargetsMiss_neverRunsMoreEvaluationsThanTheLimit() async throws {
        // Given: an evaluator that holds every evaluation until told otherwise.
        let evaluations = Evaluations(holds: true)
        let cache = Internals.PACProxyCache(
            maximumConcurrentEvaluations: 2,
            evaluate: evaluations.evaluator
        )

        // When: six distinct targets ask at once.
        let callers = Task {
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<6 {
                    group.addTask {
                        _ = await cache.proxy(
                            forScriptURL: Self.scriptURL,
                            targetURL: URL(string: "http://example.com/\(index)")!
                        )
                    }
                }
            }
        }

        // Then: two run, and the others wait for a slot instead of starting.
        try await waitUntil { await evaluations.running == 2 }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await evaluations.running == 2)
        #expect(await evaluations.targets.count == 2)

        // And once they are let go, all six are answered.
        await evaluations.releaseAll()
        await callers.value

        #expect(await evaluations.targets.count == 6)
        #expect(await evaluations.peak == 2)
        #expect(await cache.peakConcurrentEvaluations == 2)
        #expect(await cache.evaluationCount == 6)
    }

    // MARK: - A failed evaluation

    /// A PAC download that failed once (a dropped connection, the 30s timeout) is remembered as
    /// "go direct" only for a short window, not for the full five minutes, so requests do not
    /// skip the corporate proxy for long when the script itself is fine.
    @Test
    func proxy_whenEvaluationFails_isAskedAgainOnceTheShortFailureWindowPasses() async throws {
        // Given: an evaluator that fails the first time and then works, and a clock the test moves.
        let evaluator = ScriptedEvaluator(results: [.failure, .proxy("proxy.example.com")])
        let clock = TestClock()
        let cache = Internals.PACProxyCache(
            failureLifetime: 100,
            now: clock.now,
            evaluate: evaluator.evaluate
        )
        let target = try Self.url("https://example.com/")

        // When
        let first = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: target)

        clock.advance(by: 50)
        let beforeWindowEnds = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: target)

        clock.advance(by: 100)
        let afterWindowEnds = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: target)

        // Then: still fails safe to direct meanwhile, without asking again, then recovers.
        #expect(first == nil)
        #expect(beforeWindowEnds == nil)
        #expect(await evaluator.callCount == 2)
        #expect(afterWindowEnds?.host == "proxy.example.com")
    }

    /// A script that answers DIRECT is an answer, not a failure: it is kept for the full lifetime.
    @Test
    func proxy_whenScriptAnswersDirect_isNotAskedAgainAfterTheFailureWindow() async throws {
        // Given
        let evaluator = ScriptedEvaluator(results: [.direct, .proxy("proxy.example.com")])
        let clock = TestClock()
        let cache = Internals.PACProxyCache(
            failureLifetime: 100,
            now: clock.now,
            evaluate: evaluator.evaluate
        )
        let target = try Self.url("https://example.com/")

        // When
        _ = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: target)
        clock.advance(by: 1_000)
        let again = await cache.proxy(forScriptURL: Self.scriptURL, targetURL: target)

        // Then
        #expect(again == nil)
        #expect(await evaluator.callCount == 1)
    }

    // MARK: - What a failure is told apart from

    /// A script that answers DIRECT and a script that could not be asked both used to come back as
    /// `nil`. A caller that must not go direct on a failure needs them apart.
    @Test
    func resolution_whenEvaluationFails_isAFailureAndNotADirectAnswer() async throws {
        // Given
        let evaluator = ScriptedEvaluator(results: [.failure, .direct])
        let cache = Internals.PACProxyCache(evaluate: evaluator.evaluate)

        // When
        let failed = await cache.resolution(
            forScriptURL: Self.scriptURL,
            targetURL: try Self.url("https://example.com/")
        )

        let answered = await cache.resolution(
            forScriptURL: Self.scriptURL,
            targetURL: try Self.url("https://other.example.com/")
        )

        // Then
        guard case .failed(let failure) = failed else {
            Issue.record("expected a failure, got \(failed)")
            return
        }

        #expect(failure.reason == .failed)
        #expect(failure.details != nil)
        #expect(answered == .answered(nil))
    }

    @Test
    func resolution_whenEvaluationTimesOut_saysSo() async throws {
        // Given
        let evaluator = ScriptedEvaluator(results: [.timedOut])
        let cache = Internals.PACProxyCache(evaluate: evaluator.evaluate)

        // When
        let resolution = await cache.resolution(
            forScriptURL: Self.scriptURL,
            targetURL: try Self.url("https://example.com/")
        )

        // Then
        #expect(resolution == .failed(.init(reason: .timedOut)))
    }

    @Test
    func resolution_whenTheScriptCannotRun_keepsWhatTheSystemReported() async throws {
        // Given
        let evaluator = ScriptedEvaluator(results: [.executionFailed("PAC file error")])
        let cache = Internals.PACProxyCache(evaluate: evaluator.evaluate)

        // When
        let resolution = await cache.resolution(
            forScriptURL: Self.scriptURL,
            targetURL: try Self.url("https://example.com/")
        )

        // Then
        #expect(resolution == .failed(.init(reason: .failed, details: "PAC file error")))
    }

    /// Everyone who asks inside the window gets the same failure at once, which is what lets a
    /// policy that fails the request fail all of them fast instead of each waiting the script out.
    @Test
    func resolution_whenEvaluationFails_everyoneInTheWindowGetsTheFailureWithoutAskingAgain() async throws {
        // Given
        let evaluator = ScriptedEvaluator(results: [.executionFailed("down"), .proxy("proxy.example.com")])
        let clock = TestClock()
        let cache = Internals.PACProxyCache(
            failureLifetime: 100,
            now: clock.now,
            evaluate: evaluator.evaluate
        )
        let target = try Self.url("https://example.com/")

        // When
        let first = await cache.resolution(forScriptURL: Self.scriptURL, targetURL: target)

        clock.advance(by: 50)
        let second = await cache.resolution(forScriptURL: Self.scriptURL, targetURL: target)

        clock.advance(by: 100)
        let third = await cache.resolution(forScriptURL: Self.scriptURL, targetURL: target)

        // Then
        #expect(first == .failed(.init(reason: .failed, details: "down")))
        #expect(second == first)
        #expect(await evaluator.callCount == 2)

        guard case .answered(let proxy) = third else {
            Issue.record("expected the script to be asked again and answer, got \(third)")
            return
        }

        #expect(proxy?.host == "proxy.example.com")
    }

    /// A caller that is cancelled while it waits is not an answer of the script, and a policy that
    /// refuses to go direct must not read it as one.
    @Test
    func resolution_whenTheCallerIsCancelledWhileItWaits_isCancelledAndNotDirect() async throws {
        // Given
        let evaluations = Evaluations(holds: true)
        let cache = Internals.PACProxyCache(evaluate: evaluations.evaluator)
        let target = try Self.url("https://example.com/")

        let caller = Task {
            await cache.resolution(forScriptURL: Self.scriptURL, targetURL: target)
        }

        try await waitUntil { await evaluations.running == 1 }

        // When
        caller.cancel()

        // Then
        #expect(await caller.value == .cancelled)

        // And it does not disturb the evaluation, which is let go and answers for whoever asks next.
        await evaluations.releaseAll()
        try await waitUntil { await evaluations.running == 0 }
    }

    // MARK: - Helpers

    /// The default is far above what the condition takes on a quiet machine: a CI runner running
    /// the whole suite in parallel has stalled every task in the process for 10 s at a time.
    private func waitUntil(
        timeout: TimeInterval = 60,
        _ condition: @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while await !condition() {
            guard Date() < deadline else {
                Issue.record("condition not met within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// A clock that only moves when the test says so, in the nanoseconds the cache ages entries by.
private final class TestClock: @unchecked Sendable {

    private let lock = Lock()
    private var value: UInt64 = 1_000_000

    var now: @Sendable () -> UInt64 {
        { self.lock.withLock { self.value } }
    }

    func advance(by nanoseconds: UInt64) {
        lock.withLock { value += nanoseconds }
    }
}

/// Answers each evaluation with the next scripted result.
private actor ScriptedEvaluator {

    enum Result {
        case failure
        case timedOut
        case executionFailed(String)
        case direct
        case proxy(String)
    }

    struct Failure: Error {}

    private var results: [Result]
    private(set) var callCount = 0

    init(results: [Result]) {
        self.results = results
    }

    nonisolated var evaluate: @Sendable (URL, URL, Double) async throws -> Internals.Proxy? {
        { _, _, _ in try await self.next() }
    }

    private func next() throws -> Internals.Proxy? {
        callCount += 1

        switch results.removeFirst() {
        case .failure:
            throw Failure()
        case .timedOut:
            throw Internals.PACEvaluator.Error.timedOut
        case .executionFailed(let details):
            throw Internals.PACEvaluator.Error.executionFailed(details)
        case .direct:
            return nil
        case .proxy(let host):
            return Internals.Proxy(host: host, port: 8_080, connection: .http, authorization: nil)
        }
    }
}

/// Stands in for `Internals.PACEvaluator`: records what it is asked and, if told to, holds each
/// evaluation until `releaseAll()`.
private actor Evaluations {

    private(set) var targets: [URL] = []
    private(set) var running = 0
    private(set) var peak = 0

    private var holds: Bool
    private var held: [CheckedContinuation<Void, Never>] = []

    init(holds: Bool = false) {
        self.holds = holds
    }

    nonisolated var evaluator: @Sendable (URL, URL, Double) async throws -> Internals.Proxy? {
        { _, target, _ in
            await self.evaluate(target)
            return nil
        }
    }

    func releaseAll() {
        holds = false
        let continuations = held
        held = []
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func evaluate(_ target: URL) async {
        targets.append(target)
        running += 1
        peak = max(peak, running)

        if holds {
            await withCheckedContinuation { held.append($0) }
        }

        running -= 1
    }
}

#endif
