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
            onPACFailure: policy,
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
            onPACFailure: .direct,
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
                onPACFailure: .fail,
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
                onPACFailure: .fail,
                logger: nil,
                cache: cache
            )
        }

        // Then
        #expect(asked.value == 1)
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
            onPACFailure: .fail,
            logger: nil,
            cache: cache
        )

        let empty = try await Internals.SystemProxyResolver.resolve(
            target,
            among: [],
            onPACFailure: .fail,
            logger: nil,
            cache: cache
        )

        // Then
        #expect(direct == nil)
        #expect(empty == nil)
        #expect(asked.value == 0)
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
