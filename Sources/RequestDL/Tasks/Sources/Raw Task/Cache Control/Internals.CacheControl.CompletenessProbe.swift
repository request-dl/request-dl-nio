//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
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

            // The response being cached may have set cookies, and the probe is sent after it: with
            // the header the request started with, it would ask as someone who never received them,
            // and a server that rotated the session would answer by deleting the new one.
            if let cookies = configuration.cookies, cookies.managesHeader, let url = URL(string: configuration.url) {
                configuration.headers.remove(name: "Cookie")

                if let value = cookies.cookieHeader(for: url) {
                    configuration.headers.add(name: "Cookie", value: value)
                }
            }

            if let validator = Self.strongValidator(of: response) {
                configuration.headers.add(name: "If-Range", value: validator)
            }

            let request = configuration
            let client = client
            let logger = logger
            let limit = timeLimitInNanoseconds

            let head: Internals.ResponseHead? = await withTaskGroup(of: Internals.ResponseHead?.self) { group in
                group.addTask {
                    await Self.head(of: request, using: client, logger: logger)
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

        /// The head of the response to `request`, read off the stream and then the request is
        /// cancelled, so that the body is never downloaded.
        ///
        /// Not `revalidationHead`: that returns the body too, and on `.urlSession` it collects all
        /// of it in memory before it returns anything. A server that answers `200` with the whole
        /// resource (an `If-Range` that no longer matches, a `Last-Modified` it treats as weak)
        /// would have it read in full into memory, up to the time limit, for the sake of a status
        /// the head already had.
        ///
        /// `decompression` is `.disabled`: nothing here reads the body, and a response with a
        /// `Content-Encoding` is not one the probe decides for.
        private static func head(
            of request: RequestConfiguration,
            using client: any RequestExecutingClient,
            logger: Internals.TaskLogger?
        ) async -> Internals.ResponseHead? {
            guard
                let task = try? await client.execute(
                    configuration: request,
                    decompression: .disabled,
                    cache: nil,
                    logger: logger,
                    transferControl: nil
                )
            else {
                return nil
            }

            let seed = task.seed

            return await withTaskCancellationHandler {
                // Whichever way this ends, the request does: the head was all it was for.
                defer { seed() }

                do {
                    for try await step in task.response {
                        if case .download(let download) = step {
                            return download.head
                        }
                    }
                } catch {
                    return nil
                }

                return nil
            } onCancel: {
                seed()
            }
        }

        /// The `ETag` of the response when it is a strong one, otherwise its `Last-Modified` when
        /// that is a strong one too.
        ///
        /// `If-Range` has no use for a weak entity tag, and a `Last-Modified` is only strong when
        /// the response's `Date` is at least a second after it, since the resource could have
        /// changed again within the same second (RFC 9110 §13.1.5). A server compares a weak
        /// validator as a mismatch, and answers `200` with the whole body, which says nothing of
        /// the response being whole, on every probe of such a resource. Without a validator the
        /// probe asks for the range alone, as it does for a response that has none.
        private static func strongValidator(of head: Internals.ResponseHead) -> String? {
            if let entityTag = head.headerValues(named: "ETag").first?.trimmingASCIIWhitespace(),
                !entityTag.isEmpty,
                !entityTag.hasPrefix("W/")
            {
                return entityTag
            }

            guard
                let lastModified = head.headerValues(named: "Last-Modified").first?.trimmingASCIIWhitespace(),
                let modified = Date(httpDate: lastModified),
                let date = head.headerValues(named: "Date").first.flatMap({
                    Date(httpDate: $0.trimmingASCIIWhitespace())
                }),
                date.timeIntervalSince(modified) >= 1
            else {
                return nil
            }

            return lastModified
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
