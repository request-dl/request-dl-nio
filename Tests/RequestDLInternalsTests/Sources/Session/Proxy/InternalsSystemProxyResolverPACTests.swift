//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(Darwin) && canImport(CFNetwork)

import CFNetwork
import Foundation

/// A request whose system proxy is a PAC script, against a cache with a stand-in evaluator: the
/// resolver, the cache and the policy together, which is the part no other test reaches, since the
/// system's own settings cannot be made to name a script.
struct InternalsSystemProxyResolverPACTests {

    typealias Policy = Internals.SystemProxyResolver.PACFailurePolicy

    struct EvaluationFailed: Error {}

    private let scriptURL = URL(string: "http://127.0.0.1:1/proxy.pac")!
    private let target = URL(string: "https://example.com/")!

    /// The list CFNetwork gives for a URL when the system's proxy is a PAC script.
    private var pacList: [[String: Any]] {
        [
            [
                kCFProxyTypeKey as String: kCFProxyTypeAutoConfigurationURL,
                kCFProxyAutoConfigurationURLKey as String: scriptURL,
            ]
        ]
    }

    private func cache(
        evaluate: @escaping @Sendable (URL, URL, Double) async throws -> Internals.Proxy?
    ) -> Internals.PACProxyCache {
        Internals.PACProxyCache(evaluate: evaluate)
    }

    @Test(arguments: [Policy.direct, .fail])
    func resolve_whenTheScriptAnswers_isItsProxyUnderEveryPolicy(_ policy: Policy) async throws {
        // Given
        let proxy = Internals.Proxy(host: "proxy.example.com", port: 8_080, connection: .http, authorization: nil)
        let cache = cache { _, _, _ in proxy }

        // When
        let resolved = try await Internals.SystemProxyResolver.resolve(
            target,
            among: pacList,
            pac: .init(onFailure: policy),
            logger: nil,
            cache: cache
        )

        // Then
        #expect(resolved == proxy)
    }

    @Test
    func resolve_whenTheScriptCannotBeAskedAndThePolicyIsDirect_goesDirect() async throws {
        // Given
        let cache = cache { _, _, _ in throw EvaluationFailed() }

        // When
        let resolved = try await Internals.SystemProxyResolver.resolve(
            target,
            among: pacList,
            pac: .init(onFailure: .direct),
            logger: nil,
            cache: cache
        )

        // Then
        #expect(resolved == nil)
    }

    @Test
    func resolve_whenTheScriptCannotBeAskedAndThePolicyIsToFail_throwsWhatHappened() async throws {
        // Given: a script that does not finish in time.
        let cache = cache { _, _, _ in throw Internals.PACEvaluator.Error.timedOut }

        // When / Then
        let failure = await #expect(throws: Internals.PACEvaluationFailure.self) {
            try await Internals.SystemProxyResolver.resolve(
                target,
                among: pacList,
                pac: .init(onFailure: .fail),
                logger: nil,
                cache: cache
            )
        }

        #expect(failure?.reason == .timedOut)
    }

    /// The failure is remembered, so a second request inside the window fails at once and does not
    /// ask the script again.
    @Test
    func resolve_whenTheScriptCannotBeAskedTwice_asksItOnce() async throws {
        // Given
        let asked = Counter()

        let cache = cache { _, _, _ in
            asked.increment()
            throw EvaluationFailed()
        }

        // When
        for _ in 0..<2 {
            _ = try? await Internals.SystemProxyResolver.resolve(
                target,
                among: pacList,
                pac: .init(onFailure: .fail),
                logger: nil,
                cache: cache
            )
        }

        // Then
        #expect(asked.value == 1)
    }

    // MARK: - The last answer, and the two times

    /// A script that answered, and then cannot be asked once its answer has expired, still gives the
    /// request its proxy under `lastKnown`.
    @Test
    func resolve_whenTheScriptAnsweredBeforeAndCannotBeAskedNow_usesTheLastAnswer() async throws {
        // Given: an answer, five minutes and more pass, and the script is down.
        let proxy = Internals.Proxy(host: "proxy.example.com", port: 8_080, connection: .http, authorization: nil)
        let steps = Steps([.proxy(proxy), .fail])
        let clock = Clock()
        let cache = Internals.PACProxyCache(now: clock.now) { _, _, _ in try steps.next() }

        _ = try await Internals.SystemProxyResolver.resolve(
            target,
            among: pacList,
            pac: .init(onFailure: .lastKnown(orElse: .fail)),
            logger: nil,
            cache: cache
        )

        for _ in 0..<200 where await cache.count < 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        clock.advance(by: 360_000_000_000)

        // When
        let resolved = try await Internals.SystemProxyResolver.resolve(
            target,
            among: pacList,
            pac: .init(onFailure: .lastKnown(orElse: .fail)),
            logger: nil,
            cache: cache
        )

        // Then
        #expect(resolved == proxy)
    }

    @Test
    func resolve_whenTheScriptNeverAnsweredAndTheFallbackIsToFail_throws() async throws {
        // Given
        let cache = cache { _, _, _ in throw EvaluationFailed() }

        // When / Then
        await #expect(throws: Internals.PACEvaluationFailure.self) {
            try await Internals.SystemProxyResolver.resolve(
                target,
                among: pacList,
                pac: .init(onFailure: .lastKnown(orElse: .fail)),
                logger: nil,
                cache: cache
            )
        }
    }

    @Test
    func resolve_whenTheOptionsSetTheEvaluationTimeout_theScriptIsAskedWithIt() async throws {
        // Given
        let timeouts = Timeouts()

        let cache = cache { _, _, timeout in
            timeouts.record(timeout)
            return nil
        }

        // When
        _ = try await Internals.SystemProxyResolver.resolve(
            target,
            among: pacList,
            pac: .init(evaluationTimeout: 7),
            logger: nil,
            cache: cache
        )

        // Then
        #expect(timeouts.all == [7])
    }

    @Test
    func resolve_whenTheSystemProxyIsNotAScript_doesNotAskTheCache() async throws {
        // Given
        let asked = Counter()

        let cache = cache { _, _, _ in
            asked.increment()
            return nil
        }

        // When
        let direct = try await Internals.SystemProxyResolver.resolve(
            target,
            among: [[kCFProxyTypeKey as String: kCFProxyTypeNone]],
            pac: .init(onFailure: .fail),
            logger: nil,
            cache: cache
        )

        let empty = try await Internals.SystemProxyResolver.resolve(
            target,
            among: [],
            pac: .init(onFailure: .fail),
            logger: nil,
            cache: cache
        )

        // Then
        #expect(direct == nil)
        #expect(empty == nil)
        #expect(asked.value == 0)
    }
}

/// What the stand-in evaluator does, one step per evaluation.
private final class Steps: @unchecked Sendable {

    enum Step {
        case proxy(Internals.Proxy)
        case fail
    }

    private let lock = NSLock()
    private var steps: [Step]

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func next() throws -> Internals.Proxy? {
        let step = lock.withLock { steps.removeFirst() }

        switch step {
        case .proxy(let proxy):
            return proxy

        case .fail:
            throw InternalsSystemProxyResolverPACTests.EvaluationFailed()
        }
    }
}

/// A clock that only moves when the test says so, in the nanoseconds the cache ages entries by.
private final class Clock: @unchecked Sendable {

    private let lock = NSLock()
    private var value: UInt64 = 1_000_000

    var now: @Sendable () -> UInt64 {
        { self.lock.withLock { self.value } }
    }

    func advance(by nanoseconds: UInt64) {
        lock.withLock { value += nanoseconds }
    }
}

private final class Timeouts: @unchecked Sendable {

    private let lock = NSLock()
    private var recorded: [Double] = []

    var all: [Double] {
        lock.withLock { recorded }
    }

    func record(_ timeout: Double) {
        lock.withLock { recorded.append(timeout) }
    }
}

private final class Counter: @unchecked Sendable {

    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

#endif
