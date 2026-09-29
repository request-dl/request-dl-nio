//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

/// Unit coverage for `Internals.RangeResumptionPlan` and `Internals.DownloadResumptionState`: when
/// a download may be resumed at all, how the continuation is asked for, and -- the part that
/// guards against corrupting a download -- which continuations are accepted.
struct InternalsRangeResumptionPlanTests {

    private static let date = "Sat, 26 Sep 2026 10:00:00 GMT"
    private static let lastModified = "Sat, 26 Sep 2026 09:00:00 GMT"

    private func head(
        _ status: UInt = 200,
        _ headers: [(String, String)]
    ) -> Internals.ResponseHead {
        Internals.ResponseHead(
            url: "http://127.0.0.1/resource",
            status: .init(code: status, reason: ""),
            version: .init(minor: 1, major: 1),
            headers: headers.map { .init(name: $0.0, value: $0.1) },
            isKeepAlive: true
        )
    }

    private func makePlan(
        method: String = "GET",
        requestHeaders: [String] = [],
        _ headers: [(String, String)],
        status: UInt = 200
    ) -> Internals.RangeResumptionPlan? {
        Internals.RangeResumptionPlan(
            method: method,
            requestHeaderNames: requestHeaders,
            response: head(status, headers)
        )
    }

    private var strongPlan: Internals.RangeResumptionPlan {
        get throws {
            try #require(makePlan([("ETag", "\"v1\""), ("Content-Length", "1000")]))
        }
    }

    // MARK: - Eligibility

    @Test
    func strongEntityTag_isResumable_andAsksForTheRestWithIfRange() throws {
        // When
        let plan = try strongPlan

        // Then
        #expect(plan.validator == .entityTag("\"v1\""))
        #expect(plan.completeLength == 1_000)

        let headers = plan.requestHeaders(resumingAt: 250)
        #expect(headers.map(\.name) == ["Range", "If-Range"])
        #expect(headers.map(\.value) == ["bytes=250-", "\"v1\""])
    }

    @Test
    func weakEntityTag_isNotResumable() {
        #expect(makePlan([("ETag", "W/\"v1\""), ("Content-Length", "1000")]) == nil)
    }

    /// A weak `ETag` doesn't let a `Last-Modified` stand in: RFC 9110 §13.1.5 only allows a date in
    /// `If-Range` when there's no entity tag at all.
    @Test
    func weakEntityTagWithAStrongLastModified_isNotResumable() {
        #expect(
            makePlan([
                ("ETag", "W/\"v1\""),
                ("Last-Modified", Self.lastModified),
                ("Date", Self.date),
            ]) == nil
        )
    }

    @Test
    func unquotedOrRepeatedEntityTags_areNotTrusted() {
        #expect(makePlan([("ETag", "v1")]) == nil)
        #expect(makePlan([("ETag", "\"v1\""), ("ETag", "\"v2\"")]) == nil)
    }

    @Test
    func strongLastModified_isResumable() throws {
        // When
        let plan = try #require(makePlan([("Last-Modified", Self.lastModified), ("Date", Self.date)]))

        // Then
        #expect(plan.validator == .lastModified(Self.lastModified))
        #expect(plan.completeLength == nil)
        #expect(plan.requestHeaders(resumingAt: 0).map(\.value) == ["bytes=0-", Self.lastModified])
    }

    /// Less than a second between the two dates: the resource could have changed within that
    /// second without the date changing (RFC 9110 §8.8.2.2), so it's a weak validator.
    @Test
    func lastModifiedWithinASecondOfDate_isNotResumable() {
        #expect(makePlan([("Last-Modified", Self.date), ("Date", Self.date)]) == nil)
        #expect(makePlan([("Last-Modified", Self.lastModified)]) == nil)
    }

    @Test
    func noValidator_isNotResumable() {
        #expect(makePlan([("Content-Length", "1000")]) == nil)
    }

    @Test
    func onlyAPlainGetOfAWholeRepresentation_isResumable() {
        let headers = [("ETag", "\"v1\""), ("Content-Length", "1000")]

        #expect(makePlan(method: "get", headers) != nil)
        #expect(makePlan(method: "POST", headers) == nil)
        #expect(makePlan(method: "HEAD", headers) == nil)
        #expect(makePlan(requestHeaders: ["range"], headers) == nil)
        #expect(makePlan(headers, status: 206) == nil)
        #expect(makePlan(headers, status: 203) == nil)
    }

    @Test
    func contentCodedResponses_areNotResumable() {
        #expect(makePlan([("ETag", "\"v1\""), ("Content-Encoding", "gzip")]) == nil)
        #expect(makePlan([("ETag", "\"v1\""), ("Content-Encoding", "identity")]) != nil)
    }

    @Test
    func conflictingContentLengths_leaveTheLengthUnknown() throws {
        let plan = try #require(makePlan([("ETag", "\"v1\""), ("Content-Length", "10"), ("Content-Length", "20")]))
        #expect(plan.completeLength == nil)
    }

    // MARK: - Validation

    @Test
    func exactContinuation_isAccepted() throws {
        let continuation = head(206, [("Content-Range", "bytes 250-999/1000"), ("ETag", "\"v1\"")])
        #expect(try strongPlan.validate(continuation, resumingAt: 250) == .resume)

        // Without repeating the validator is fine too: the `206` itself says `If-Range` matched.
        let withoutValidator = head(206, [("Content-Range", "bytes 250-999/1000")])
        #expect(try strongPlan.validate(withoutValidator, resumingAt: 250) == .resume)
    }

    /// The one outcome this whole type exists to catch: the resource changed, the server honoured
    /// `If-Range` by sending the whole new version, and that must never be spliced on.
    @Test
    func fullResponse_isTheResourceHavingChanged() throws {
        let response = head(200, [("ETag", "\"v2\""), ("Content-Length", "1000")])

        #expect(throws: Internals.DownloadResumptionMismatchError(.representationChanged)) {
            try strongPlan.validate(response, resumingAt: 250)
        }
    }

    @Test
    func continuationStartingAnywhereElse_isRejected() throws {
        for range in ["bytes 0-999/1000", "bytes 251-999/1000", "bytes 249-999/1000"] {
            #expect(throws: Internals.DownloadResumptionMismatchError(.contentRangeMismatch)) {
                try strongPlan.validate(head(206, [("Content-Range", range)]), resumingAt: 250)
            }
        }
    }

    @Test
    func continuationOfARepresentationOfAnotherLength_isRejected() throws {
        for range in ["bytes 250-1999/2000", "bytes 250-499/1000", "bytes 250-999/*"] {
            #expect(throws: Internals.DownloadResumptionMismatchError(.contentRangeMismatch)) {
                try strongPlan.validate(head(206, [("Content-Range", range)]), resumingAt: 250)
            }
        }
    }

    @Test
    func malformedOrMissingContentRange_isRejected() throws {
        for headers in [[], [("Content-Range", "items 250-999/1000")], [("Content-Range", "bytes 250/1000")]] {
            #expect(throws: Internals.DownloadResumptionMismatchError(.contentRangeMismatch)) {
                try strongPlan.validate(head(206, headers), resumingAt: 250)
            }
        }
    }

    /// A `206` under a different validator: a server or cache that ignored `If-Range` and sent the
    /// requested range of whatever it has now.
    @Test
    func continuationUnderAnotherValidator_isRejected() throws {
        let response = head(206, [("Content-Range", "bytes 250-999/1000"), ("ETag", "\"v2\"")])

        #expect(throws: Internals.DownloadResumptionMismatchError(.validatorMismatch)) {
            try strongPlan.validate(response, resumingAt: 250)
        }
    }

    @Test
    func contentCodedContinuation_isRejected() throws {
        let response = head(206, [("Content-Range", "bytes 250-999/1000"), ("Content-Encoding", "gzip")])

        #expect(throws: Internals.DownloadResumptionMismatchError(.contentCoded)) {
            try strongPlan.validate(response, resumingAt: 250)
        }
    }

    /// Everything had in fact arrived -- a chunked body whose terminator was lost, say -- and the
    /// server says there's nothing past it.
    @Test
    func unsatisfiableRangeAtTheVeryEnd_isAlreadyComplete() throws {
        let response = head(416, [("Content-Range", "bytes */1000")])
        #expect(try strongPlan.validate(response, resumingAt: 1_000) == .alreadyComplete)

        let unknownLength = try #require(makePlan([("ETag", "\"v1\"")]))
        #expect(try unknownLength.validate(response, resumingAt: 1_000) == .alreadyComplete)
    }

    @Test
    func unsatisfiableRangeAnywhereElse_isRejected() throws {
        for (range, offset) in [("bytes */1000", Int64(500)), ("bytes */800", 800), ("bytes 0-1/1000", 1_000)] {
            #expect(throws: Internals.DownloadResumptionMismatchError(.unsatisfiableRange)) {
                try strongPlan.validate(head(416, [("Content-Range", range)]), resumingAt: offset)
            }
        }
    }

    @Test
    func anyOtherStatus_isRejected() throws {
        #expect(throws: Internals.DownloadResumptionMismatchError(.unexpectedStatus(503))) {
            try strongPlan.validate(head(503, []), resumingAt: 250)
        }
    }

    // MARK: - Attempt budget

    @Test
    func nextAttempt_withoutAPlan_isNil() {
        var state = Internals.DownloadResumptionState(policy: .init())
        state.didReceiveOriginalHead(head(200, []), method: "GET", requestHeaderNames: [])

        let attempt = state.nextAttempt()
        #expect(attempt == nil)
    }

    @Test
    func nextAttempt_resumesFromWhatWasDelivered() throws {
        var state = Internals.DownloadResumptionState(policy: .init())
        state.didReceiveOriginalHead(head(200, [("ETag", "\"v1\"")]), method: "GET", requestHeaderNames: [])
        state.didDeliver(4_096)

        let next = state.nextAttempt()
        let attempt = try #require(next)
        #expect(attempt.offset == 4_096)
        #expect(attempt.headers.first?.value == "bytes=4096-")
    }

    /// Consecutive attempts that deliver nothing count against the budget; any progress restores
    /// it, so a long download over a flaky network isn't capped.
    @Test
    func nextAttempt_budgetCountsOnlyAttemptsWithoutProgress() {
        var state = Internals.DownloadResumptionState(policy: .init(maximumAttemptsWithoutProgress: 2, delay: 0))
        state.didReceiveOriginalHead(head(200, [("ETag", "\"v1\"")]), method: "GET", requestHeaderNames: [])

        var granted = (0..<3).map { _ in state.nextAttempt() != nil }
        #expect(granted == [true, true, false])

        state.didDeliver(1)
        granted = (0..<3).map { _ in state.nextAttempt() != nil }
        #expect(granted == [true, true, false])
    }
}
