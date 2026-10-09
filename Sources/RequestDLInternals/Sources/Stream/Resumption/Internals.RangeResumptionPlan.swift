//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#endif

extension Internals {

    /// How an execution reconnects a download whose connection is lost mid-body. See
    /// `Internals.TransferControl.resumption`.
    package struct DownloadResumptionPolicy: Sendable, Hashable {

        // MARK: - Internal properties

        /// Reconnection attempts in a row that may fail without a single new byte arriving before
        /// the download fails for good. Any progress starts the count over, so a long download
        /// over a flaky network isn't capped, while a server that keeps failing is given up on.
        package var maximumAttemptsWithoutProgress: Int

        /// Nanoseconds to wait before each reconnection attempt.
        package var delay: UInt64

        // MARK: - Inits

        package init(maximumAttemptsWithoutProgress: Int = 3, delay: UInt64 = 1_000_000_000) {
            precondition(maximumAttemptsWithoutProgress > .zero, "A resumption policy allows at least one attempt")
            self.maximumAttemptsWithoutProgress = maximumAttemptsWithoutProgress
            self.delay = delay
        }
    }

    /// Where a download starts when it doesn't start at the beginning: continuing one a previous
    /// launch of the application left unfinished. Its first exchange is then already a continuation,
    /// so there is no original response to read a plan from, and what a reconnection counts from is
    /// ``offset``, not zero.
    package struct DownloadResumptionStart: Sendable, Hashable {

        package let plan: Internals.RangeResumptionPlan
        package let offset: Int64

        package init(plan: Internals.RangeResumptionPlan, offset: Int64) {
            self.plan = plan
            self.offset = offset
        }
    }

    /// Whether, and how, a download can continue on a new exchange from where a lost one stopped,
    /// with an HTTP `Range` request (RFC 9110 §14), and whether a continuation actually does.
    ///
    /// Executor-agnostic and pure: it only reads heads and produces headers. Each executor feeds it
    /// the original response head, counts the body bytes it delivers, and asks it how to phrase
    /// and whether to accept the continuation.
    ///
    /// ## Never splicing two representations
    ///
    /// The one thing a continuation must never do is append bytes of a *different* version of the
    /// resource to the ones already delivered. So a plan only exists when the original response
    /// carries a strong validator, the continuation always asks with `If-Range` (a server whose
    /// resource changed answers `200` with the whole new body instead of `206`), and every
    /// continuation is checked before a single byte of it is accepted: status, `Content-Range`
    /// starting exactly where delivery stopped, complete length, validator. Anything else fails the
    /// download with ``DownloadResumptionMismatchError``, which is no worse than failing on a
    /// lost connection without resumption.
    ///
    /// ## When a download is resumable
    ///
    /// - `GET` (the only method RFC 9110 defines range requests for), without a `Range` of its own.
    /// - A `200` response.
    /// - A strong validator: a strong `ETag`, or, only without any `ETag`, a `Last-Modified` that is
    ///   strong per RFC 9110 §8.8.2.2 (the response's `Date` at least a second later). `If-Range`
    ///   must never carry a weak one (§13.1.5).
    /// - No content coding. Byte offsets are offsets into the *representation*; a transport that
    ///   decodes natively (CFNetwork, `NIOHTTPResponseDecompressor`) delivers decoded bytes, whose
    ///   count isn't one. Conservative on purpose: a manually decoded body does count raw bytes,
    ///   and could be allowed later.
    package struct RangeResumptionPlan: Sendable, Hashable, Codable {

        // MARK: - Inner types

        package enum Validator: Sendable, Hashable, Codable {
            case entityTag(String)
            case lastModified(String)
        }

        /// What a validated continuation means for the download.
        package enum Continuation: Sendable, Hashable {
            /// A `206` for exactly the missing range: append its body.
            case resume
            /// A `416` saying the representation is exactly as long as what was already
            /// delivered: nothing was missing but the end of the exchange itself (typically a
            /// chunked body's terminator), so the download is complete.
            case alreadyComplete
        }

        // MARK: - Internal properties

        package let validator: Validator

        /// The original `Content-Length`, when there was one: what a continuation's
        /// `Content-Range` complete length has to match.
        package let completeLength: Int64?

        // MARK: - Inits

        /// A plan for a download whose original response is long gone (a previous launch of the
        /// application), from what was kept of it.
        package init(validator: Validator, completeLength: Int64?) {
            self.validator = validator
            self.completeLength = completeLength
        }

        /// - Returns: `nil` when the exchange isn't resumable (see the type's doc comment).
        package init?(
            method: String,
            requestHeaderNames: some Sequence<String>,
            response: Internals.ResponseHead
        ) {
            guard
                method.uppercased() == "GET",
                !requestHeaderNames.contains(where: { $0.lowercased() == "range" }),
                response.status.code == 200,
                !Self.hasContentCoding(response)
            else { return nil }

            let entityTags = response.headerValues(named: "ETag").map { $0.trimming(where: \.isWhitespace) }

            if let entityTag = entityTags.first {
                // Any `ETag` at all rules the date out (RFC 9110 §13.1.5): a weak one only means
                // there's no strong validator, not that `Last-Modified` may stand in for it.
                guard entityTags.count == 1, Self.isStrongEntityTag(entityTag) else {
                    return nil
                }

                validator = .entityTag(entityTag)
            } else {
                guard let lastModified = Self.strongLastModified(response) else {
                    return nil
                }

                validator = .lastModified(lastModified)
            }

            completeLength = Self.contentLength(response)
        }

        // MARK: - Internal methods

        /// The headers a continuation from `offset` adds to the original request.
        package func requestHeaders(resumingAt offset: Int64) -> [(name: String, value: String)] {
            let validatorValue: String

            switch validator {
            case .entityTag(let entityTag):
                validatorValue = entityTag
            case .lastModified(let lastModified):
                validatorValue = lastModified
            }

            return [
                ("Range", "bytes=\(offset)-"),
                ("If-Range", validatorValue),
            ]
        }

        /// Checks a continuation's head before any of its body is accepted.
        ///
        /// - Throws: ``DownloadResumptionMismatchError`` for anything that isn't exactly the
        /// missing range of the same representation.
        package func validate(
            _ response: Internals.ResponseHead,
            resumingAt offset: Int64
        ) throws -> Continuation {
            switch response.status.code {
            case 206:
                break

            case 416:
                // `bytes */L`: nothing is left from `offset` on. Only a success when `offset` is
                // the whole representation, and that representation is still the one we have.
                guard
                    let range = ContentRange(response),
                    range.first == nil,
                    let length = range.completeLength,
                    length == offset,
                    completeLength.map({ $0 == length }) ?? true
                else {
                    throw DownloadResumptionMismatchError(.unsatisfiableRange)
                }

                return .alreadyComplete

            case 200:
                // Either `If-Range` no longer matched (the resource changed) or the server
                // doesn't do ranges at all. Both hand back a whole body that can't be spliced.
                throw DownloadResumptionMismatchError(.representationChanged)

            default:
                throw DownloadResumptionMismatchError(.unexpectedStatus(response.status.code))
            }

            guard !Self.hasContentCoding(response) else {
                throw DownloadResumptionMismatchError(.contentCoded)
            }

            guard
                let range = ContentRange(response),
                let first = range.first,
                let last = range.last,
                first == offset,
                last >= first
            else {
                throw DownloadResumptionMismatchError(.contentRangeMismatch)
            }

            if let completeLength {
                // The rest of *this* representation: same total length, running to its end.
                guard range.completeLength == completeLength, last == completeLength - 1 else {
                    throw DownloadResumptionMismatchError(.contentRangeMismatch)
                }
            } else if let length = range.completeLength, last != length - 1 {
                throw DownloadResumptionMismatchError(.contentRangeMismatch)
            }

            // A `206` is sent only because `If-Range` matched, but a validator that does come
            // back with it has to agree too: a server (or cache) that ignores `If-Range` would
            // otherwise splice two versions without either side noticing.
            switch validator {
            case .entityTag(let entityTag):
                let entityTags = response.headerValues(named: "ETag").map { $0.trimming(where: \.isWhitespace) }

                guard entityTags.allSatisfy({ $0 == entityTag }) else {
                    throw DownloadResumptionMismatchError(.validatorMismatch)
                }

            case .lastModified(let lastModified):
                let values = response.headerValues(named: "Last-Modified").map { $0.trimming(where: \.isWhitespace) }

                guard values.allSatisfy({ $0 == lastModified }) else {
                    throw DownloadResumptionMismatchError(.validatorMismatch)
                }
            }

            return .resume
        }

        // MARK: - Private static methods

        private static func hasContentCoding(_ response: Internals.ResponseHead) -> Bool {
            response
                .headerValues(named: "Content-Encoding")
                .flatMap { $0.split(separator: ",") }
                .map { $0.trimming(where: \.isWhitespace).lowercased() }
                .contains { !$0.isEmpty && $0 != "identity" }
        }

        /// `"..."`, not `W/"..."`. Unquoted values aren't valid entity tags at all, so they aren't
        /// trusted as strong ones either.
        private static func isStrongEntityTag(_ value: String) -> Bool {
            value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\"")
        }

        /// Whether `validator` is something a plan could have been made with from a response: what
        /// a stored one has to be before it is sent back as `If-Range`.
        ///
        /// A plan built from a response passes through `isStrongEntityTag` or the date parser and
        /// came out of a parsed header, so it cannot hold a line break. One read back from storage
        /// has had none of that, and goes into a request header as it is.
        ///
        /// - An entity tag is a strong one (`"..."`, never `W/"..."`) whose tag holds only the
        ///   characters RFC 9110 §8.8.3 allows in it: no space, no control character, no `"`.
        /// - A `Last-Modified` is an HTTP date, and holds no control character.
        package static func isWellFormed(_ validator: Validator) -> Bool {
            switch validator {
            case .entityTag(let value):
                let scalars = Array(value.unicodeScalars)

                guard scalars.count >= 2, scalars.first == "\"", scalars.last == "\"" else {
                    return false
                }

                return scalars.dropFirst().dropLast().allSatisfy { scalar in
                    scalar.value > 0x20 && scalar != "\"" && scalar.value != 0x7F
                        && !(0x80...0x9F).contains(scalar.value)
                }

            case .lastModified(let value):
                return Date(httpDate: value) != nil
                    && value.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F }
            }
        }

        /// RFC 9110 §8.8.2.2: a `Last-Modified` is only strong when the response's own `Date` is
        /// at least a second after it (anything closer could have changed within the same
        /// second without the date changing).
        private static func strongLastModified(_ response: Internals.ResponseHead) -> String? {
            guard
                let value = response.headerValues(named: "Last-Modified").first?.trimming(where: \.isWhitespace),
                let lastModified = Date(httpDate: value),
                let dateValue = response.headerValues(named: "Date").first?.trimming(where: \.isWhitespace),
                let date = Date(httpDate: dateValue),
                date.timeIntervalSince1970 - lastModified.timeIntervalSince1970 >= 1
            else { return nil }

            return value
        }

        private static func contentLength(_ response: Internals.ResponseHead) -> Int64? {
            let values = Set(
                response
                    .headerValues(named: "Content-Length")
                    .flatMap { $0.split(separator: ",") }
                    .map { $0.trimming(where: \.isWhitespace) }
            )

            // Conflicting values mean the length isn't known, not that either one is.
            guard values.count == 1, let value = values.first else {
                return nil
            }

            return Int64(value)
        }
    }

    /// Thrown in place of a continuation that isn't exactly the rest of the representation
    /// already partly delivered. Nothing of that continuation reaches the reader.
    package struct DownloadResumptionMismatchError: Error, Sendable, Hashable, CustomStringConvertible {

        package enum Reason: Sendable, Hashable {
            /// `200`: the resource changed since (`If-Range` no longer matched), or the server
            /// ignores `Range`.
            case representationChanged
            /// A `206` whose `Content-Range` doesn't start where delivery stopped, or doesn't run
            /// to the end of a representation of the original length.
            case contentRangeMismatch
            /// A `206` carrying a validator other than the original one.
            case validatorMismatch
            /// A `206` with a content coding the original response didn't have.
            case contentCoded
            /// A `416` for a range that isn't simply "already complete".
            case unsatisfiableRange
            case unexpectedStatus(UInt)
        }

        package let reason: Reason

        package var description: String {
            "The download couldn't be resumed where it stopped: \(reason)"
        }

        package init(_ reason: Reason) {
            self.reason = reason
        }
    }

    /// One download's resumption bookkeeping: the plan, how many bytes of the representation
    /// have been delivered, and the attempt budget. A value type, synchronized by whichever
    /// executor owns it.
    package struct DownloadResumptionState: Sendable {

        /// Where, and how, the next continuation starts.
        package struct Attempt: Sendable {
            /// Which reconnection this is over the whole download, from 1. Unlike the budget, not
            /// reset by progress.
            package let number: Int
            package let offset: Int64
            package let plan: Internals.RangeResumptionPlan
            package let headers: [(name: String, value: String)]
        }

        // MARK: - Internal properties

        package let policy: Internals.DownloadResumptionPolicy
        package private(set) var plan: Internals.RangeResumptionPlan?

        /// Body bytes delivered so far, across every exchange: the offset a continuation starts at.
        /// Kept by whichever producer hands the bytes over, which is the only thing that knows
        /// exactly how many the reader got.
        package var deliveredBytes: Int64 = .zero

        // MARK: - Private properties

        private var attemptsWithoutProgress = 0
        private var attempts = 0
        private var deliveredBytesAtLastAttempt: Int64 = -1
        private let hasStart: Bool

        // MARK: - Inits

        /// - Parameter start: Where the download starts, when that isn't the beginning. Its plan is
        ///   then taken as given, and bytes are counted from its offset.
        package init(policy: Internals.DownloadResumptionPolicy, start: DownloadResumptionStart? = nil) {
            self.policy = policy
            self.plan = start?.plan
            self.deliveredBytes = start?.offset ?? .zero
            self.hasStart = start != nil
        }

        // MARK: - Internal methods

        /// Decides, from the original exchange's head, whether this download can be resumed at
        /// all. Only the first head counts; continuations are validated against it instead.
        package mutating func didReceiveOriginalHead(
            _ response: Internals.ResponseHead,
            method: String,
            requestHeaderNames: some Sequence<String>
        ) {
            // The head of a continuation, which is validated against the plan it started with, not
            // a source for a new one.
            guard !hasStart else {
                return
            }

            plan = RangeResumptionPlan(method: method, requestHeaderNames: requestHeaderNames, response: response)
        }

        package mutating func didDeliver(_ bytes: Int) {
            deliveredBytes += Int64(bytes)
        }

        /// The next continuation, or `nil` once there is no plan or the budget is spent.
        package mutating func nextAttempt() -> Attempt? {
            guard let plan else {
                return nil
            }

            if deliveredBytes != deliveredBytesAtLastAttempt {
                attemptsWithoutProgress = .zero
            }

            guard attemptsWithoutProgress < policy.maximumAttemptsWithoutProgress else {
                return nil
            }

            attemptsWithoutProgress += 1
            attempts += 1
            deliveredBytesAtLastAttempt = deliveredBytes

            return Attempt(
                number: attempts,
                offset: deliveredBytes,
                plan: plan,
                headers: plan.requestHeaders(resumingAt: deliveredBytes)
            )
        }
    }
}

// MARK: - Content-Range

extension Internals.RangeResumptionPlan {

    /// `Content-Range: bytes first-last/complete` or `bytes */complete` (RFC 9110 §14.4), the
    /// only unit and forms a single-range continuation can carry.
    fileprivate struct ContentRange {
        let first: Int64?
        let last: Int64?
        let completeLength: Int64?

        init?(_ response: Internals.ResponseHead) {
            let values = response.headerValues(named: "Content-Range")

            guard values.count == 1, let value = values.first?.trimming(where: \.isWhitespace) else {
                return nil
            }

            let unitAndRest = value.split(separator: " ", maxSplits: 1)

            guard unitAndRest.count == 2, unitAndRest[0].lowercased() == "bytes" else {
                return nil
            }

            let rangeAndLength = unitAndRest[1].trimming(where: \.isWhitespace).split(separator: "/")

            guard rangeAndLength.count == 2 else {
                return nil
            }

            if rangeAndLength[1] == "*" {
                completeLength = nil
            } else {
                guard let length = Int64(rangeAndLength[1]), length >= .zero else {
                    return nil
                }

                completeLength = length
            }

            if rangeAndLength[0] == "*" {
                // Only meaningful with a known length (a `416`).
                guard completeLength != nil else {
                    return nil
                }

                first = nil
                last = nil
                return
            }

            let bounds = rangeAndLength[0].split(separator: "-", omittingEmptySubsequences: false)

            guard
                bounds.count == 2,
                let first = Int64(bounds[0]),
                let last = Int64(bounds[1]),
                first >= .zero
            else { return nil }

            self.first = first
            self.last = last
        }
    }
}
