//
// See LICENSE for this package's licensing information.
//

import Logging
import SwiftAsyncStream
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// What a request does with how a PAC script came out: use its answer, go direct and say so, or
/// fail. Against a stand-in resolution, since the policy does not depend on how it was reached.
struct InternalsSystemProxyResolverPolicyTests {

    typealias Policy = Internals.SystemProxyResolver.PACFailurePolicy

    // The credentials and the query are what must stay out of the log.
    private let scriptURL = URL(string: "https://user:secret@pac.example.com/proxy.pac?token=abc#fragment")!
    private let failure = Internals.PACEvaluationFailure(reason: .timedOut, details: "slow")
    private let proxy = Internals.Proxy(host: "proxy.example.com", port: 8_080, connection: .http, authorization: nil)

    @Test(arguments: [Policy.direct, .fail])
    func apply_whenTheScriptAnswered_isItsAnswerUnderEveryPolicy(_ policy: Policy) throws {
        // When
        let proxied = try Internals.SystemProxyResolver.apply(
            .answered(proxy),
            policy: policy,
            scriptURL: scriptURL,
            logger: nil
        )

        let direct = try Internals.SystemProxyResolver.apply(
            .answered(nil),
            policy: policy,
            scriptURL: scriptURL,
            logger: nil
        )

        // Then: "direct" is an answer too, and it is not reported as a failure.
        #expect(proxied == proxy)
        #expect(direct == nil)
    }

    @Test
    func apply_whenTheScriptFailedAndThePolicyIsDirect_goesDirectAndSaysSo() async throws {
        // Given
        let records = LogRecords()

        // When
        let result = try await Logger.withTestHandler(recorded: records.append) { logger in
            try Internals.SystemProxyResolver.apply(
                .failed(failure, lastKnown: nil),
                policy: .direct,
                scriptURL: scriptURL,
                logger: logger
            )
        }

        // Then
        #expect(result == nil)

        let recorded = records.all
        #expect(recorded.count == 1)
        #expect(recorded.first?.level == .warning)
        #expect(recorded.first?.metadata["script"] == "https://pac.example.com/proxy.pac")
        #expect(recorded.first?.metadata["reason"] == "timed out")
        #expect(recorded.first?.metadata["details"] == "slow")

        // The credentials and the query of the script did not reach the log.
        let everything = recorded.map(\.description).joined()
        #expect(!everything.contains("secret"))
        #expect(!everything.contains("token"))
    }

    @Test
    func apply_whenTheScriptFailedAndThePolicyIsToFail_throwsTheFailureAndDoesNotGoDirect() async throws {
        // Given
        let records = LogRecords()

        // When / Then
        try await Logger.withTestHandler(recorded: records.append) { logger in
            #expect(throws: Internals.PACEvaluationFailure.self) {
                try Internals.SystemProxyResolver.apply(
                    .failed(failure, lastKnown: nil),
                    policy: .fail,
                    scriptURL: scriptURL,
                    logger: logger
                )
            }
        }

        // It did not go direct, so there is nothing to warn about.
        #expect(records.all.isEmpty)
    }

    // MARK: - The last known answer

    private var lastKnown: Internals.PACLastKnownAnswer {
        .init(proxy: proxy, ageNanoseconds: 90 * 1_000_000_000)
    }

    @Test(arguments: [Policy.Fallback.direct, .fail])
    func apply_whenTheScriptFailedAndThereIsALastAnswer_usesItAndSaysHowOldItIs(
        _ fallback: Policy.Fallback
    ) async throws {
        // Given
        let records = LogRecords()

        // When
        let result = try await Logger.withTestHandler(recorded: records.append) { logger in
            try Internals.SystemProxyResolver.apply(
                .failed(failure, lastKnown: lastKnown),
                policy: .lastKnown(orElse: fallback),
                scriptURL: scriptURL,
                logger: logger
            )
        }

        // Then: the answer of the script, whatever the fallback would have done.
        #expect(result == proxy)

        let recorded = records.all
        #expect(recorded.count == 1)
        #expect(recorded.first?.level == .warning)
        #expect(recorded.first?.metadata["answerAgeSeconds"] == "90")
        #expect(recorded.first?.metadata["script"] == "https://pac.example.com/proxy.pac")

        let everything = recorded.map(\.description).joined()
        #expect(!everything.contains("secret"))
        #expect(!everything.contains("token"))
    }

    /// "Connect directly" can be the last answer too, and then that is what is used.
    @Test
    func apply_whenTheLastAnswerWasDirect_usesDirect() throws {
        // When
        let result = try Internals.SystemProxyResolver.apply(
            .failed(failure, lastKnown: .init(proxy: nil, ageNanoseconds: 1)),
            policy: .lastKnown(orElse: .fail),
            scriptURL: scriptURL,
            logger: nil
        )

        // Then
        #expect(result == nil)
    }

    @Test
    func apply_whenThereIsNoLastAnswerAndTheFallbackIsDirect_goesDirectAndSaysSo() async throws {
        // Given
        let records = LogRecords()

        // When
        let result = try await Logger.withTestHandler(recorded: records.append) { logger in
            try Internals.SystemProxyResolver.apply(
                .failed(failure, lastKnown: nil),
                policy: .lastKnown(orElse: .direct),
                scriptURL: scriptURL,
                logger: logger
            )
        }

        // Then
        #expect(result == nil)
        #expect(records.all.count == 1)
        #expect(records.all.first?.metadata["answerAgeSeconds"] == nil)
    }

    @Test
    func apply_whenThereIsNoLastAnswerAndTheFallbackIsToFail_throwsTheFailure() {
        #expect(throws: Internals.PACEvaluationFailure.self) {
            try Internals.SystemProxyResolver.apply(
                .failed(failure, lastKnown: nil),
                policy: .lastKnown(orElse: .fail),
                scriptURL: scriptURL,
                logger: nil
            )
        }
    }

    @Test
    func apply_whenTheCallerWasCancelledUnderLastKnown_followsTheFallback() throws {
        // When
        let direct = try Internals.SystemProxyResolver.apply(
            .cancelled,
            policy: .lastKnown(orElse: .direct),
            scriptURL: scriptURL,
            logger: nil
        )

        // Then
        #expect(direct == nil)

        #expect(throws: CancellationError.self) {
            try Internals.SystemProxyResolver.apply(
                .cancelled,
                policy: .lastKnown(orElse: .fail),
                scriptURL: scriptURL,
                logger: nil
            )
        }
    }

    @Test
    func apply_whenTheCallerWasCancelled_staysDirectUnlessThePolicyIsToFail() throws {
        // When
        let direct = try Internals.SystemProxyResolver.apply(
            .cancelled,
            policy: .direct,
            scriptURL: scriptURL,
            logger: nil
        )

        // Then
        #expect(direct == nil)

        #expect(throws: CancellationError.self) {
            try Internals.SystemProxyResolver.apply(
                .cancelled,
                policy: .fail,
                scriptURL: scriptURL,
                logger: nil
            )
        }
    }
}

private final class LogRecords: @unchecked Sendable {

    private let lock = Lock()
    private var records: [TestLogHandler.LogRecord] = []

    var all: [TestLogHandler.LogRecord] {
        lock.withLock { records }
    }

    var append: @Sendable (TestLogHandler.LogRecord) -> Void {
        { record in self.lock.withLock { self.records.append(record) } }
    }
}
