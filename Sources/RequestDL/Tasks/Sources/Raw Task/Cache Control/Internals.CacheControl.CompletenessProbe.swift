//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals.CacheControl {

    /// The extra request that decides whether a `.urlSession` response with no `Content-Length`
    /// arrived whole, for ``Property/cacheCompletenessProbe(_:)``.
    ///
    /// CFNetwork reports a chunked body that was cut on a chunk boundary as complete, so nothing
    /// in the response itself says whether it is. The server can, if it understands `Range`: the
    /// probe asks it for the one byte that would come right after the bytes received.
    ///
    /// - `416 Range Not Satisfiable` with `Content-Range: bytes */<total>`, `total` being the
    ///   number of bytes received: there is nothing after them. The body is whole.
    /// - `206 Partial Content`: there is a byte after them. The body was cut.
    /// - Anything else (`200` because the server does not do ranges, a different `total`, a
    ///   failure, an answer that took too long) does not decide, and an undecided response is not
    ///   stored.
    struct CompletenessProbe: Sendable {

        /// What the server said.
        enum Verdict: Sendable, Equatable {
            case complete
            case truncated
            case undecided
        }

        // MARK: - Internal static properties

        /// How long the probe may take before it is given up on. A server that accepts the
        /// request and never answers would otherwise hold the cache write, and everything
        /// waiting on it, for as long as the transport's own timeout lets it.
        static let defaultTimeLimitInNanoseconds: UInt64 = 30_000_000_000

        // MARK: - Internal properties

        let client: any RequestExecutingClient
        let requestConfiguration: RequestConfiguration
        let logger: Internals.TaskLogger?

        /// Only a test sets it to anything but ``defaultTimeLimitInNanoseconds``.
        var timeLimitInNanoseconds = Self.defaultTimeLimitInNanoseconds

        // MARK: - Internal static methods

        /// Whether the response that was received can be checked at all: the server has to say it
        /// does ranges, and the bytes in the cache have to be the bytes the ranges count.
        ///
        /// `Content-Encoding` rules it out: `.urlSession` hands over the decoded body, and a byte
        /// range counts the encoded one, so the number of bytes received says nothing about where
        /// the range would start.
        static func isApplicable(to head: Internals.ResponseHead) -> Bool {
            let acceptsBytes = head.headerValues(named: "Accept-Ranges").contains {
                $0.split(separator: ",").contains { $0.trimmingASCIIWhitespace().lowercased() == "bytes" }
            }

            let isEncoded = head.headerValues(named: "Content-Encoding").contains {
                let coding = $0.trimmingASCIIWhitespace().lowercased()
                return !coding.isEmpty && coding != "identity"
            }

            return acceptsBytes && !isEncoded
        }

        /// What the answer to a probe for the byte at `offset` says about a body of `offset` bytes.
        static func verdict(of head: Internals.ResponseHead, receivedBytes offset: Int) -> Verdict {
            // A representation that is encoded on this answer does not count the way it did on
            // the first one.
            let isEncoded = head.headerValues(named: "Content-Encoding").contains {
                let coding = $0.trimmingASCIIWhitespace().lowercased()
                return !coding.isEmpty && coding != "identity"
            }

            guard !isEncoded else {
                return .undecided
            }

            switch head.status.code {
            case 416:
                // `bytes */<total>`: the only form that says how long the representation is.
                guard
                    let total = head.headerValues(named: "Content-Range").lazy.compactMap(unsatisfiedTotal).first,
                    total == offset
                else {
                    return .undecided
                }

                return .complete

            case 206:
                // `bytes <first>-<last>/<total>` for a byte that is there: the body went on.
                guard let range = head.headerValues(named: "Content-Range").first, range.lowercased().hasPrefix("bytes")
                else {
                    return .undecided
                }

                return .truncated

            default:
                return .undecided
            }
        }

        // MARK: - Internal methods

        /// Asks the server whether the response had more bytes than the `receivedBytes` the cache
        /// was given.
        ///
        /// - Parameter response: The head of the response being cached, whose validator the probe
        ///   sends as `If-Range`: a server that has a different representation by now answers `200`
        ///   with all of it, which does not decide, instead of a `416` that would be about the
        ///   other one.
        func run(response: Internals.ResponseHead, receivedBytes: Int) async -> Verdict {
            guard Self.isApplicable(to: response) else {
                logger?.log(
                    level: .debug,
                    "Completeness probe skipped: the response does not advertise byte ranges or is encoded"
                )
                return .undecided
            }

            var configuration = requestConfiguration

            // The request that was made, asking for one byte instead of the body. Whatever the
            // caller set for these would change the answer to a different question.
            for name in ["Range", "If-Range", "If-None-Match", "If-Modified-Since", "If-Match", "If-Unmodified-Since"] {
                configuration.headers.remove(name: name)
            }

            configuration.headers.add(name: "Range", value: "bytes=\(receivedBytes)-\(receivedBytes)")

            if let validator = Self.strongValidator(of: response) {
                configuration.headers.add(name: "If-Range", value: validator)
            }

            let request = configuration
            let client = client
            let logger = logger
            let limit = timeLimitInNanoseconds

            let head: Internals.ResponseHead? = await withTaskGroup(of: Internals.ResponseHead?.self) { group in
                group.addTask {
                    try? await client.revalidationHead(configuration: request, logger: logger, metrics: nil)
                }

                group.addTask {
                    try? await Task.sleep(nanoseconds: limit)
                    return nil
                }

                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            guard let head else {
                return .undecided
            }

            return Self.verdict(of: head, receivedBytes: receivedBytes)
        }

        // MARK: - Private static methods

        /// The `ETag` of the response when it is a strong one, otherwise its `Last-Modified`.
        /// `If-Range` has no use for a weak entity tag (RFC 9110 §13.1.5).
        private static func strongValidator(of head: Internals.ResponseHead) -> String? {
            if let entityTag = head.headerValues(named: "ETag").first?.trimmingASCIIWhitespace(),
                !entityTag.isEmpty,
                !entityTag.hasPrefix("W/")
            {
                return entityTag
            }

            return head.headerValues(named: "Last-Modified").first?.trimmingASCIIWhitespace()
        }

        /// `<total>` of `bytes */<total>`.
        private static func unsatisfiedTotal(_ contentRange: String) -> Int? {
            let parts = contentRange.split(separator: " ", maxSplits: 1)

            guard
                parts.count == 2,
                parts[0].lowercased() == "bytes",
                parts[1].hasPrefix("*/")
            else {
                return nil
            }

            return Int(parts[1].dropFirst(2).trimmingASCIIWhitespace())
        }
    }
}

extension StringProtocol {

    fileprivate func trimmingASCIIWhitespace() -> String {
        var slice = Substring(self)

        while let first = slice.first, first == " " || first == "\t" {
            slice = slice.dropFirst()
        }

        while let last = slice.last, last == " " || last == "\t" {
            slice = slice.dropLast()
        }

        return String(slice)
    }
}
