//
// See LICENSE for this package's licensing information.
//

import Crypto
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
#endif

extension Internals {

    struct CacheControl: Sendable {

        enum Output {
            case task(SessionTask)
            /// Nothing served from the cache: the request has to go out. `revalidation` is what was
            /// measured on the way, when the cache was consulted by a conditional request that did
            /// not settle the matter, and comes before whatever the request itself measures.
            case cache(
                (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)?,
                revalidation: [Internals.TransactionMetrics]
            )
        }

        // MARK: - Internal properties

        let requestConfiguration: RequestConfiguration
        let dataCache: DataCache
        let logger: Internals.TaskLogger?

        /// Whether the request runs on `.urlSession`, the one executor that cannot tell a chunked
        /// body that ended from one that was cut (see ``lacksProofOfCompleteness(_:)``).
        var isURLSessionExecutor = false

        /// What runs the completeness probe of a response `.urlSession` cannot vouch for. `nil`
        /// leaves such a response out of the cache without asking.
        var completenessProbeClient: (any RequestExecutingClient)?

        /// Awaited by the cache writer before it allocates its buffer, and so before it reads the
        /// first chunk. Nothing sets it outside the tests, which hold the writer back with it to
        /// have a download run far ahead of the cache without depending on how the two happen to
        /// be scheduled.
        var beforeWriting: (@Sendable () async -> Void)?

        // MARK: - Internal methods

        func callAsFunction(_ client: any RequestExecutingClient) async -> Output {
            let startedAt = Date()
            let revalidation = Internals.RequestMetricsCollector()

            logger?.log(
                level: .debug,
                "Evaluating cache for request",
                additionalMetadata: [
                    "cache_strategy": .stringConvertible(String(describing: requestConfiguration.cacheStrategy))
                ]
            )

            if effectiveCacheStrategy != .ignoreCachedData {
                if let cachedData = await storedCachedData() {
                    let cachedSessionTask = await checkIfCachedDataStillValid(
                        client: client,
                        cached: cachedData,
                        startedAt: startedAt,
                        revalidation: revalidation
                    )

                    if let cachedSessionTask {
                        logger?.log(level: .debug, "Cache hit - returning cached session task")
                        return .task(cachedSessionTask)
                    }
                } else if case .useCachedDataOnly = effectiveCacheStrategy {
                    logger?.log(
                        level: .warning,
                        "No cached data available, but strategy is 'useCachedDataOnly', returning error"
                    )
                    return .task(emptyCachedDataTask())
                }
            } else {
                logger?.log(level: .info, "Cache ignored by strategy: ignoreCachedData")
            }

            return .cache(
                try? await cacheIfNeeded(
                    dataCache: dataCache,
                    requestConfiguration: requestConfiguration
                ),
                revalidation: revalidation.transactions()
            )
        }

        // MARK: - Private methods

        /// The response handed back when the caller demanded cached data and there is none.
        ///
        /// - Note: Was written out twice, identically. Once is enough.
        private func emptyCachedDataTask() -> SessionTask {
            SessionTask(
                Internals.AsyncResponse(
                    logger: logger,
                    uploadingBytes: .zero,
                    upload: .empty(),
                    decompressionDispatch: .skip,
                    readingMode: requestConfiguration.readingMode,
                    head: .throwing(EmptyCachedDataError()),
                    download: .empty()
                )
            )
        }

        private func storedCachedData() async -> CachedData? {
            guard requestConfiguration.isCacheEnabled else {
                return nil
            }

            guard
                let cachedData = await dataCache.getCachedData(
                    forKey: requestConfiguration.url,
                    policy: requestConfiguration.cachePolicy
                ),
                matchesVary(of: cachedData.cachedResponse)
            else {
                return nil
            }

            return cachedData
        }

        /// Whether the stored response may be given to this request, given the headers its
        /// `Vary` says it depends on (RFC 9111 §4.1).
        ///
        /// A stored response is kept per URL, so a request that disagrees is a miss, and its own
        /// response replaces the stored one.
        private func matchesVary(of cachedResponse: CachedResponse) -> Bool {
            guard matchesCredentials(of: cachedResponse) else {
                return false
            }

            let responseHeaders = RequestDL.HTTPHeaders(
                cachedResponse.response.headers.map { ($0.name, $0.value) }
            )

            switch varyFields(of: responseHeaders) {
            case .none:
                return true

            case .any:
                return false

            case .fields(let fields):
                guard let recorded = cachedResponse.varyRequestHeaders else {
                    return false
                }

                return fields.allSatisfy { recorded[$0] == requestValue(forVaryField: $0) }
            }
        }

        /// The request headers that identify an account: `Authorization`, `Cookie` and
        /// `Proxy-Authorization`, by lowercased name. A `Cookie` is one the caller put on the
        /// request by hand, or one the session's `CookieJar` added: `RawTask` adds it before this
        /// is built, so a response fetched with a jar's cookies is never found by a request
        /// without them.
        private static let credentialFields = ["authorization", "cookie", "proxy-authorization"]

        /// Whether the stored response was stored for the credentials this request sends.
        ///
        /// `DataCache` keys entries by URL alone and is commonly one store for the whole process
        /// (`DataCache.shared`), so an app where more than one account is signed in over its
        /// lifetime could be given one account's response by another. A response stored for a
        /// request that carried credentials therefore records which ones (as digests, see
        /// ``requestValue(forVaryField:)``), and is given only to a request that sends the same:
        /// not to another account, and not to a request with no credentials at all. A response
        /// stored for a request with none carries no such record and is given to any request, as
        /// it always was.
        private func matchesCredentials(of cachedResponse: CachedResponse) -> Bool {
            guard
                let recorded = cachedResponse.varyRequestHeaders,
                Self.credentialFields.allSatisfy({ recorded[$0] != nil })
            else {
                return true
            }

            return Self.credentialFields.allSatisfy { recorded[$0] == requestValue(forVaryField: $0) }
        }

        private enum Vary {
            case none
            case any
            case fields([String])
        }

        private func varyFields(of responseHeaders: RequestDL.HTTPHeaders) -> Vary {
            let fields = directives(responseHeaders["Vary"] ?? [])
                .map { $0.lowercased() }
                .filter { !$0.isEmpty }

            if fields.contains("*") {
                return .any
            }

            return fields.isEmpty ? .none : .fields(Array(Set(fields)).sorted())
        }

        /// What this request sends for `field`, normalized the way it is recorded.
        ///
        /// For a credential header (`credentialFields`) it is a digest, never the value: the
        /// record is written to disk as it is, and unless the cache has an `encryptionKey` that
        /// is in the clear. A header the request does not send is `""`, so that "no credential"
        /// is told apart from any credential.
        private func requestValue(forVaryField field: String) -> String {
            let value = (requestConfiguration.headers[field] ?? [])
                .map { $0.trimming(where: \.isWhitespace) }
                .joined(separator: ", ")

            guard Self.credentialFields.contains(field), !value.isEmpty else {
                return value
            }

            return Self.digest(ofCredential: value, field: field)
        }

        /// A SHA-256 of the credential, with the field name and a fixed prefix in front so the
        /// same bytes under another header, or in another place, do not give the same digest.
        ///
        /// A bearer token or a random session identifier cannot be recovered from it. A
        /// credential with little entropy (a Basic password) can be guessed from a record someone
        /// can read, which is what `DataCache.EncryptionKey` is for.
        static func digest(ofCredential value: String, field: String) -> String {
            let hash = SHA256.hash(data: Data("request-dl.cache.credential.v1\n\(field)\n\(value)".utf8))
            let hex = hash.map { byte in
                let digits = String(byte, radix: 16)
                return digits.count == 1 ? "0" + digits : digits
            }

            return "sha256:" + hex.joined()
        }

        /// The strategy actually applied, folding request-side ``CacheHeader`` directives on top
        /// of ``RequestConfiguration/cacheStrategy``.
        ///
        /// - Important: Only ever escalates towards a more network-averse strategy, never
        /// loosens what `.cacheStrategy(_:)` explicitly configured. Order-independent by
        /// construction, since it reads both inputs fresh rather than letting one `PropertyNode`
        /// overwrite what another wrote.
        private var effectiveCacheStrategy: CacheStrategy {
            // Read straight off the outgoing `Cache-Control` request header, not a typed
            // side-channel set by `CacheHeader`'s own `PropertyNode`. `HeaderGroup` (and
            // `Proxy.connectHeaders`/`Form`'s per-part headers) reconstruct their subtree by
            // searching for `LeafNode<HeaderNode>` specifically; a `CacheHeader` wrapped in
            // anything but a plain `HeaderNode` becomes invisible to that search and gets
            // silently dropped whenever it's nested inside one of those. Deriving from the
            // already-serialized header sidesteps the node-graph representation entirely, so it
            // keeps working no matter how the header got there: `CacheHeader`, a raw
            // `Headers { "Cache-Control": ... }`, nested in a group, or anything else.
            let requestDirectives = directives(requestConfiguration.headers["Cache-Control"] ?? [])
                .map { $0.lowercased() }

            // Gated on `isCacheEnabled`: `only-if-cached` addresses *any* cache in the request
            // path (a CDN or proxy downstream), which is a distinct thing from this package's own
            // on-disk cache. Escalating unconditionally would force `EmptyCachedDataError` on
            // every request carrying the directive even when the developer never opted into
            // local caching via `.cachePolicy(_:)`, turning a pure wire-level signal into an
            // always-on local failure.
            if requestDirectives.contains("only-if-cached"), requestConfiguration.isCacheEnabled {
                return .useCachedDataOnly
            }

            let requiresRevalidation = requestDirectives.contains {
                $0 == "no-cache" || $0.hasPrefix("no-cache=")
            }

            if requiresRevalidation, requestConfiguration.cacheStrategy == .returnCachedDataElseLoad {
                return .reloadAndValidateCachedData
            }

            return requestConfiguration.cacheStrategy
        }

        /// Whether the outgoing request declares `no-store` (RFC 7234 §5.2.1.5): this response
        /// must not be persisted to this package's on-disk cache.
        private var requestForbidsStoring: Bool {
            directives(requestConfiguration.headers["Cache-Control"] ?? [])
                .contains { $0.lowercased() == "no-store" }
        }

        /// Whether the outgoing request carries an `Authorization`, `Cookie` or
        /// `Proxy-Authorization` header.
        ///
        /// A response to such a request is stored, as a private cache may store it (RFC 9111
        /// §3.5 restricts only shared caches), but for those credentials and no others: see
        /// ``matchesCredentials(of:)``.
        private var requestCarriesCredentials: Bool {
            Self.credentialFields.contains { !(requestConfiguration.headers[$0] ?? []).isEmpty }
        }

        private func checkIfCachedDataStillValid(
            client: any RequestExecutingClient,
            cached cachedData: CachedData,
            startedAt: Date,
            revalidation: Internals.RequestMetricsCollector
        ) async -> SessionTask? {
            switch effectiveCacheStrategy {
            case .ignoreCachedData:
                return nil

            case .useCachedDataOnly:
                return await makeCachedSession(cachedData, startedAt: startedAt, revalidation: revalidation)
                    ?? emptyCachedDataTask()

            case .returnCachedDataElseLoad:
                return await makeCachedSession(cachedData, startedAt: startedAt, revalidation: revalidation)

            case .reloadAndValidateCachedData:
                guard
                    let cachedData = await validateCachedData(
                        client: client,
                        dataCache: dataCache,
                        cached: cachedData,
                        requestConfiguration: requestConfiguration,
                        revalidation: revalidation
                    )
                else { return nil }

                // Just confirmed by the origin, so its freshness lifetime does not decide whether
                // it is served now: see `isCachedDataValid(_:checkingFreshness:)`.
                return await makeCachedSession(
                    cachedData,
                    startedAt: startedAt,
                    revalidation: revalidation,
                    validated: true
                )
            }
        }

        /// - Parameter validated: The entry was just confirmed by the origin (a `304`, or a
        ///   response whose validators match). RFC 9111 §4.3.4 lets that response be used for the
        ///   request that triggered the validation even when its freshness lifetime is already
        ///   over, as with `max-age=0` or an `Expires` in the past, so only the checks that are
        ///   about the stored body are applied. Without it such an entry was removed right after
        ///   it was renewed and the body was downloaded again.
        private func makeCachedSession(
            _ cachedData: CachedData,
            startedAt: Date,
            revalidation: Internals.RequestMetricsCollector,
            validated: Bool = false
        ) async -> SessionTask? {
            if !isCachedDataValid(cachedData, checkingFreshness: !validated) {
                await dataCache.remove(forKey: requestConfiguration.url)
                return nil
            }

            // The first piece is read before anything is promised to the caller. An entry that
            // cannot be read (it fails to authenticate, or its files are gone) is a miss: once
            // the response is handed out, the only thing left to do with it is fail the stream.
            var body = cachedData.buffer

            guard let firstPiece = await Self.readPiece(of: &body) else {
                logger?.log(level: .debug, "Cache entry could not be read - treating it as a miss")
                await dataCache.remove(forKey: requestConfiguration.url)
                return nil
            }

            let window = Internals.FlowControlWindow()

            let download = await Internals.DownloadBuffer(
                readingMode: requestConfiguration.readingMode,
                flowControl: window
            )

            let dataCache = dataCache
            let key = requestConfiguration.url

            // At the priority of the request, not a low one: the response is read by the caller of
            // this request, which is waiting on exactly what this feeds it.
            Self.startReplay(body, startingWith: firstPiece, into: download, window: window) {
                await dataCache.remove(forKey: key)
            }

            // Nothing crossed the wire for this response, but it is still part of what happened to
            // the request: the revalidation that confirmed it came first, when there was one.
            let now = Date()
            let metrics = Internals.RequestMetricsCollector()

            for transaction in revalidation.transactions() {
                metrics.append(transaction)
            }

            metrics.append(
                Internals.TransactionMetrics(
                    source: .cache,
                    url: URL(string: requestConfiguration.url),
                    fetchStart: startedAt,
                    responseStart: now,
                    responseEnd: now
                )
            )

            return SessionTask(
                seed: .init {
                    // Wakes the replay if it is waiting for room, so it ends instead of staying
                    // parked on a reader that is gone.
                    window.release()
                    download.failed(Internals.TaskCancelledError())
                    download.close()
                },
                response: .init(
                    logger: logger,
                    uploadingBytes: .zero,
                    upload: .empty(),
                    decompressionDispatch: .skip,
                    readingMode: requestConfiguration.readingMode,
                    head: .constant(cachedData.cachedResponse.response),
                    download: download.stream
                ),
                metrics: metrics
            )
        }

        /// How much of a cached body is handed to the download buffer at a time.
        ///
        /// Large enough that a big entry is not read one reading-mode chunk (1 KiB by default)
        /// per trip to the file system, and small enough that the window is consulted often.
        static let replayPieceSize = 65_536

        /// Starts ``replay(_:startingWith:into:window:onUnreadable:)`` as an unstructured task.
        ///
        /// Not detached, and with no priority of its own: it inherits the one of the caller. The
        /// reader of `download` waits for what the replay feeds it, so a fixed low priority here
        /// is a priority inversion, a cached response stalled behind unrelated background work.
        @discardableResult
        static func startReplay(
            _ body: Internals.AnyBuffer,
            startingWith firstPiece: [UInt8] = [],
            into download: Internals.DownloadBuffer,
            window: Internals.FlowControlWindow,
            onUnreadable: (@Sendable () async -> Void)? = nil
        ) -> _Concurrency.Task<Void, Never> {
            _Concurrency.Task {
                await replay(body, startingWith: firstPiece, into: download, window: window, onUnreadable: onUnreadable)
            }
        }

        /// Feeds a cached body into `download`, one piece at a time, and waits for room in `window`
        /// between pieces.
        ///
        /// Handing the whole body over in one `append` read it into the download buffer's stream
        /// regardless of how fast the response was being read, so a large entry sat in memory
        /// whole behind a slow reader, which a response from the network never does.
        ///
        /// Ends, closing `download`, when the body is done, when `window` is released (the reader
        /// is gone or the task was cancelled), or when the entry cannot be read, which fails
        /// `download` instead of ending it as if the body were complete.
        ///
        /// - Parameters:
        ///   - firstPiece: What ``readPiece(of:)`` already took from the start of `body`, handed
        ///   over first.
        ///   - onUnreadable: Runs, before `download` is failed, when a later piece cannot be read.
        ///   The caller drops the entry there: the first piece vouches for the first chunk only,
        ///   and an entry left behind would fail at the same place on every request while it is
        ///   fresh.
        static func replay(
            _ body: Internals.AnyBuffer,
            startingWith firstPiece: [UInt8] = [],
            into download: Internals.DownloadBuffer,
            window: Internals.FlowControlWindow,
            onUnreadable: (@Sendable () async -> Void)? = nil
        ) async {
            var body = body

            if !firstPiece.isEmpty, !window.isReleased {
                download.append(Internals.Chunk(firstPiece))
            }

            while body.readableBytes > .zero, !window.isReleased {
                await window.waitUntilWritable()

                guard !window.isReleased else {
                    break
                }

                guard let piece = await readPiece(of: &body), !piece.isEmpty else {
                    await onUnreadable?()
                    download.failed(AsyncBytesReadError())
                    break
                }

                download.append(Internals.Chunk(piece))
            }

            download.close()
        }

        /// Takes the next piece off `body`, at most ``replayPieceSize`` bytes.
        ///
        /// - Returns: The piece, empty for a body with nothing left to read, and `nil` when what is
        /// left cannot be read: a stored body that fails to decrypt, or whose file is gone.
        static func readPiece(of body: inout Internals.AnyBuffer) async -> [UInt8]? {
            guard body.readableBytes > .zero else {
                return []
            }

            guard let piece = await body.readBytes(min(body.readableBytes, replayPieceSize)), !piece.isEmpty else {
                return nil
            }

            return piece
        }

        private func validateCachedData(
            client: any RequestExecutingClient,
            dataCache: DataCache,
            cached cachedData: CachedData,
            requestConfiguration: RequestConfiguration,
            revalidation: Internals.RequestMetricsCollector
        ) async -> CachedData? {
            guard
                let headers = await getUpdatedHeadersForCache(
                    client: client,
                    cached: cachedData,
                    revalidation: revalidation
                )
            else { return nil }

            let modifiedHeaders = updateCacheHeaders(
                RequestDL.HTTPHeaders(cachedData.cachedResponse.response.headers.map { ($0.name, $0.value) }),
                with: headers
            )

            // Written back whether or not a header changed. What revalidating confirms is that
            // the stored response is current as of now (RFC 9111 §4.3.4), and that is carried by
            // `CachedResponse.date`, which a server repeating the same `Cache-Control` leaves
            // looking just as old as it was: skipping the write kept the entry stale, removed it
            // on the next look and sent the request to the network after all, a conditional
            // request and a full download per use.
            let cachedResponse = updateCachedResponse(
                cachedData.cachedResponse,
                with: modifiedHeaders
            )

            // What is stored afterwards has to be this entry. The conditional request is a round
            // trip, and the key can be written meanwhile by a request that did not match it
            // (another account, a different `Vary`): that record is not what was confirmed, and
            // is handed to no one on the strength of this response. Another revalidation of the
            // same entry may have got there first, and what it left is just as good. The entry
            // is checked against this request again for the same reason, since nothing above did.
            guard
                let updated = await dataCache.renewCached(
                    key: requestConfiguration.url,
                    cachedResponse: cachedResponse,
                    expecting: cachedData.cachedResponse,
                    policy: requestConfiguration.cachePolicy
                ),
                matchesVary(of: updated.cachedResponse)
            else {
                return nil
            }

            return updated
        }

        private func getUpdatedHeadersForCache(
            client: any RequestExecutingClient,
            cached cachedData: CachedData,
            revalidation: Internals.RequestMetricsCollector
        ) async -> RequestDL.HTTPHeaders? {
            var requestConfiguration = requestConfiguration
            requestConfiguration.method = "HEAD"

            // Conditional request headers. Copying `ETag` and `Last-Modified` straight onto the
            // request tells the server nothing: those are response headers. A server only
            // answers 304 when it is asked with `If-None-Match` or `If-Modified-Since`: without
            // these the 304 branch below is unreachable and every revalidation downloads the
            // whole body again.
            setConditionalHeader(
                &requestConfiguration.headers,
                named: "If-None-Match",
                from: cachedData.response.headers["ETag"]
            )

            setConditionalHeader(
                &requestConfiguration.headers,
                named: "If-Modified-Since",
                from: cachedData.response.headers["Last-Modified"]
            )

            guard
                let head = try? await client.revalidationHead(
                    configuration: requestConfiguration,
                    logger: logger,
                    metrics: revalidation
                )
            else { return nil }

            // A redirect hop of the conditional request was sent cookies the request did not carry:
            // what it confirms is about other credentials than the ones the entry was stored for,
            // and must not extend the life of the shared entry.
            if requestConfiguration.cookies?.hasSentCookiesTheRequestDidNot ?? false {
                logger?.log(level: .info, "Cache not validated - a redirect carried cookies the request did not")
                return nil
            }

            if head.status.code == 304 {
                logger?.log(level: .info, "Cache validated (304 Not Modified), reusing cached data")
                // The fresh 304 response's own headers, not the stale cached ones: a 304 is where
                // the server sends an updated `Cache-Control`/`Expires` to extend freshness (RFC
                // 9111 §4.3.4), and `updateCacheHeaders` below only refreshes a directive from what
                // this method returns. Returning the cached headers would make both sides of that
                // comparison identical, so `validateCachedData` would never refresh
                // `CachedResponse.date` and revalidation could never extend an already-stale
                // entry's life.
                return RequestDL.HTTPHeaders(head.headers.map { ($0.name, $0.value) })
            }

            // Both sides defaulted before comparing. `response.headers[name]` is optional and the
            // cached side has `?? []` applied, so a server that sends neither header would compare
            // `nil` against `[]`, which is not equal, and invalidate an entry that is in fact
            // unchanged.
            //
            // `hasValidatorEvidence` tracks whether at least one of the two validators was actually
            // present (not just equal) to compare. Without it, a non-304 response carrying neither
            // `ETag` nor `Last-Modified` would compare `[] == []` on every iteration, vacuously
            // "matching", and the cached entry would be treated as still valid with nothing behind
            // that conclusion: a HEAD answered with 404, 410, or 503 (or a plain 200 the server
            // chose not to make conditional) means the origin itself did not say "unchanged".
            var hasValidatorEvidence = false

            for name in ["Last-Modified", "ETag"] {
                let fresh = head.headerValues(named: name)
                let cached = cachedData.response.headers[name] ?? []

                guard fresh == cached else {
                    logger?.log(
                        level: .info,
                        "Cache invalidated (status: \(head.status.code)), will fetch fresh data"
                    )
                    return nil
                }

                if !fresh.isEmpty {
                    hasValidatorEvidence = true
                }
            }

            guard hasValidatorEvidence else {
                logger?.log(
                    level: .info,
                    "Cache invalidated (status: \(head.status.code), no validators to compare), will fetch fresh data"
                )
                return nil
            }

            return RequestDL.HTTPHeaders(head.headers.map { ($0.name, $0.value) })
        }

        /// Sets a conditional request header from the values the cached response carries.
        private func setConditionalHeader(
            _ headers: inout RequestDL.HTTPHeaders,
            named name: String,
            from values: [String]?
        ) {
            guard let values, !values.isEmpty else {
                return
            }

            headers.remove(name: name)

            for value in values {
                headers.add(name: name, value: value)
            }
        }

        /// Folds the freshness directives the server just sent into the cached response.
        ///
        /// - Important: The new value has to win. Must not pass the new headers through the
        /// `cachedHeaders` parameter of a helper that prefers whatever was already there: that
        /// could only ever add a directive that was missing and never refresh one that existed,
        /// and picking up a fresher `max-age` is the entire point of revalidating.
        private func updateCacheHeaders(
            _ cachedHeaders: RequestDL.HTTPHeaders,
            with newHeaders: RequestDL.HTTPHeaders
        ) -> RequestDL.HTTPHeaders {
            var merged = cachedHeaders

            replaceHeader(&merged, with: newHeaders, for: "Cache-Control")
            replaceHeader(&merged, with: newHeaders, for: "Expires")

            // `Age` is how old the response already was when it was received, counted from there
            // on. What was just confirmed is as old as this response says, which is no age at all
            // when it carries none. Left in place, the one the stored response arrived with would
            // be added to the age of an entry whose clock has just restarted.
            merged.remove(name: "Age")

            for value in newHeaders["Age"] ?? [] {
                merged.add(name: "Age", value: value)
            }

            return merged
        }

        private func replaceHeader(
            _ headers: inout RequestDL.HTTPHeaders,
            with newHeaders: RequestDL.HTTPHeaders,
            for name: String
        ) {
            guard let values = newHeaders[name], !values.isEmpty else {
                return
            }

            guard headers[name] ?? [] != values else {
                return
            }

            headers.remove(name: name)

            for value in values {
                headers.add(name: name, value: value)
            }
        }

        private func updateCachedResponse(
            _ cachedResponse: CachedResponse,
            with updatedHeaders: RequestDL.HTTPHeaders
        ) -> CachedResponse {
            .init(
                response: .init(
                    url: cachedResponse.response.url,
                    status: cachedResponse.response.status,
                    version: cachedResponse.response.version,
                    headers: updatedHeaders.map { Internals.ResponseHead.HeaderField(name: $0.name, value: $0.value) },
                    isKeepAlive: cachedResponse.response.isKeepAlive
                ),
                policy: cachedResponse.policy,
                varyRequestHeaders: cachedResponse.varyRequestHeaders
            )
        }

        private func isAny(_ vary: Vary) -> Bool {
            if case .any = vary {
                return true
            }

            return false
        }

        /// Whether a response with this status may be stored at all: RFC 9110 §15.1's
        /// heuristically cacheable set (the codes RFC 9111 §4.2.2 lets a cache store without
        /// explicit freshness information).
        ///
        /// Storing anything else was actively harmful here: an entry with no `max-age`/`Expires`
        /// is treated as valid indefinitely (`isCachedDataValid`), so one transient `503` was
        /// replayed by `.returnCachedDataElseLoad` on every later request, without ever asking
        /// the network again. `206 Partial Content` is excluded the same way: it would serve a
        /// byte range to a later request for the whole resource.
        private static func isCacheableByDefault(statusCode: UInt) -> Bool {
            [200, 203, 204, 300, 301, 308, 404, 405, 410, 414, 501].contains(statusCode)
        }

        private func cacheIfNeeded(
            dataCache: DataCache,
            requestConfiguration: RequestConfiguration
        ) async throws -> (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)? {
            guard requestConfiguration.isCacheEnabled else {
                return nil
            }

            // The closure below runs when the head arrives, on whatever is delivering the response
            // (an event loop), which is not this request's task. The write is this request's work,
            // and has to run at its priority.
            let priority = _Concurrency.Task.currentPriority

            return { head -> Internals.AsyncStream<Internals.Chunk>? in
                let headHeaders = RequestDL.HTTPHeaders(head.headers.map { ($0.name, $0.value) })

                let vary = varyFields(of: headHeaders)

                guard
                    Self.isCacheableByDefault(statusCode: head.status.code),
                    !containsNoCache(headers: headHeaders["Cache-Control"] ?? []),
                    !requestForbidsStoring,
                    // `Vary: *` is a response that no later request can be said to match.
                    !isAny(vary)
                else {
                    return nil
                }

                // A redirect hop the jar sent cookies the request did not: this response was
                // fetched with credentials that are not the ones recorded with it below.
                guard !(requestConfiguration.cookies?.hasSentCookiesTheRequestDidNot ?? false) else {
                    logger?.log(
                        level: .info,
                        "Response will not be cached - a redirect carried cookies the request did not"
                    )
                    return nil
                }

                // What nothing says is whole is only stored when the probe can be asked.
                let probe: CompletenessProbe?

                if lacksProofOfCompleteness(head) {
                    guard
                        let client = completenessProbeClient,
                        CompletenessProbe.isApplicable(to: head)
                    else {
                        logger?.log(
                            level: .info,
                            "Response will not be cached - nothing proves its body arrived whole",
                            additionalMetadata: [
                                "status": .stringConvertible(head.status.code)
                            ]
                        )
                        return nil
                    }

                    probe = CompletenessProbe(
                        client: client,
                        requestConfiguration: requestConfiguration,
                        logger: logger
                    )
                } else {
                    probe = nil
                }

                // What the response varies on, and, when the request carried credentials, which
                // ones: all three headers, `""` for those it did not send, so that the entry is
                // not given to a request with none.
                var fields: [String] = []

                if case .fields(let varyFields) = vary {
                    fields = varyFields
                }

                if requestCarriesCredentials {
                    fields = Array(Set(fields).union(Self.credentialFields)).sorted()
                }

                let varyRequestHeaders: [String: String]? =
                    fields.isEmpty
                    ? nil
                    : Dictionary(uniqueKeysWithValues: fields.map { ($0, requestValue(forVaryField: $0)) })

                // A capacity hint for the allocation below, not a correctness check, so `0` is a
                // fine stand-in when the header is absent.
                let contentLength = contentLength(headers: headHeaders["Content-Length"] ?? []) ?? 0

                // Read exactly once, by the task below. Buffering until that read begins
                // covers the hop it takes to get going, and from then on only the gap between
                // the download and the disk writer stays in memory.
                //
                // Metered, so that gap has a limit: past it the download gives up on the cache
                // (see `Internals.DownloadBuffer.cacheBacklogLimit`) instead of buffering the rest
                // of a body for a writer that is not keeping up.
                let asyncBuffers = Internals.DownloadBuffer.makeCacheStream()

                dataCache.trackWrite(priority: priority) {
                    // On every exit path. Without it, a task that gives up before reaching the
                    // loop leaves behind a stream nobody will ever drain, and the download goes
                    // on feeding it for the rest of the response. Closing makes every later
                    // append a no op, so the producer stops buffering without having to know
                    // that its reader is gone.
                    defer { asyncBuffers.close() }

                    await beforeWriting?()

                    guard
                        var cacheBuffer = await dataCache.allocateBuffer(
                            key: requestConfiguration.url,
                            cachedResponse: .init(
                                response: head,
                                policy: requestConfiguration.cachePolicy,
                                varyRequestHeaders: varyRequestHeaders
                            ),
                            contentLength: Int64(contentLength)
                        )
                    else {
                        logger?.log(
                            level: .warning,
                            "Could not allocate a cache buffer - response will not be cached"
                        )
                        return
                    }

                    do {
                        try await Self.write(asyncBuffers, to: &cacheBuffer)

                        // Not asked when no tier kept the body: there is nothing to complete, and the
                        // byte count it would be asked about (0, once both tiers were given up on)
                        // is not the length of anything stored. The probe would send a request for
                        // nothing and log a truncation that did not happen.
                        if let probe, !cacheBuffer.hasNowhereToWrite {
                            let verdict = await probe.run(response: head, receivedBytes: cacheBuffer.readableBytes)

                            guard verdict == .complete else {
                                logger?.log(
                                    level: .info,
                                    "Response will not be cached - the completeness probe said \(verdict)"
                                )
                                await dataCache.discardFailedWrite(cacheBuffer, forKey: requestConfiguration.url)
                                return
                            }
                        }

                        // Corrects the usage estimate `allocateBuffer` above set from
                        // `contentLength` (a pre-write hint, `0` for chunked/unknown-length
                        // responses) to the real byte count now that it's known. See
                        // `DataCache.finalizeWrite(_:contentLengthHint:)`.
                        await dataCache.finalizeWrite(cacheBuffer, contentLengthHint: Int64(contentLength))

                        logger?.log(
                            level: .debug,
                            "Cached response saved",
                            additionalMetadata: [
                                "size_bytes": .stringConvertible(cacheBuffer.readableBytes)
                            ]
                        )
                    } catch let error as Internals.CacheBacklogExceededError {
                        logger?.log(level: .warning, "Response will not be cached - \(error)")
                        await dataCache.discardFailedWrite(cacheBuffer, forKey: requestConfiguration.url)
                    } catch {
                        logger?.log(level: .error, "Failed to cache response: \(String(describing: error))")
                        await dataCache.discardFailedWrite(cacheBuffer, forKey: requestConfiguration.url)
                    }
                }

                return asyncBuffers
            }
        }

        /// Writes the chunks of a response to `cacheBuffer` until the stream ends, or until the
        /// buffer has no tier left to write to.
        ///
        /// The stream keeps what has not been read yet, and the download feeds it as fast as the
        /// network gives chunks, which is faster than this loop takes them out (one task hop and
        /// a copy per chunk, a kilobyte each by default). Once every tier has been given up on
        /// the loop would only read the rest of the body to throw it away, while it piled up in
        /// the stream: a body of a gigabyte held more than half a gigabyte of the process on
        /// the NIO executors. Stopping here, and closing the stream, makes every later append a
        /// no op.
        static func write(
            _ asyncBuffers: Internals.AsyncStream<Internals.Chunk>,
            to cacheBuffer: inout DataCache.Buffer
        ) async throws {
            guard !cacheBuffer.hasNowhereToWrite else {
                asyncBuffers.close()
                return
            }

            for try await chunk in asyncBuffers {
                // The chunk is the very value the reader of the download holds too. Writing it
                // reads nothing and copies nothing but into the tiers themselves.
                await cacheBuffer.writeData(chunk.data)

                if cacheBuffer.hasNowhereToWrite {
                    asyncBuffers.close()
                    return
                }
            }
        }

        /// Whether this response was delivered by an executor that cannot say its body is whole,
        /// and has nothing else that does.
        ///
        /// A body with a `Content-Length` is checked against it, on every executor. The NIO
        /// executors end a chunked body with its terminating chunk and fail the request when the
        /// connection closes before it. CFNetwork, under `.urlSession`, reports a chunked body that
        /// was cut between two chunks as a complete one. It shows the chunked framing as
        /// `Transfer-Encoding: Identity` (and nothing else about it), which, with no
        /// `Content-Length`, is what is left to go by. An HTTP/2 response has neither header, and a
        /// stream that ends early fails there.
        private func lacksProofOfCompleteness(_ head: Internals.ResponseHead) -> Bool {
            guard isURLSessionExecutor else {
                return false
            }

            guard head.headerValues(named: "Content-Length").isEmpty else {
                return false
            }

            return !head.headerValues(named: "Transfer-Encoding").isEmpty
        }

        /// - Parameter checkingFreshness: Whether the entry also has to be within its freshness
        ///   lifetime. Its body is always checked against `Content-Length`.
        private func isCachedDataValid(_ cachedData: CachedData, checkingFreshness: Bool = true) -> Bool {
            let headers = cachedData.response.headers

            // The cached byte count is only checked against `Content-Length` when that check can
            // mean something. `Content-Length` is absent entirely for chunked transfer and most
            // HTTP/2 responses, leaving nothing valid to compare against. `Content-Encoding`
            // present means the cached bytes are already decompressed, while `Content-Length`
            // still reflects the compressed size on the wire (see `Internals.Client.swift`: the
            // header survives decompression under both `.nio` and `.urlSession`).
            //
            // Skipping the check in these cases trades away its only defense against a body
            // truncated by something other than a stream error (already handled by the write
            // path's own error handling). That's an acceptable trade: the alternative was every
            // chunked or compressed response permanently missing the cache.
            //
            // One truncation does not raise a stream error: `.urlSession` reports a chunked body
            // cut between two chunks as complete. Those never get here, because
            // `lacksProofOfCompleteness(_:)` keeps them out of the cache when they are written.
            if let contentLength = contentLength(headers: headers["Content-Length"] ?? []),
                (headers["Content-Encoding"] ?? []).isEmpty,
                cachedData.buffer.readableBytes != contentLength
            {
                return false
            }

            guard checkingFreshness else {
                return true
            }

            // A freshness value that is there and cannot be read is a stale response, not a
            // missing value (RFC 9111 §4.2.1, §5.3): ignoring it kept the entry fresh for as long
            // as the other directive said, or for ever when there was none, and `Expires: 0` is
            // what servers send to say "already expired".
            //
            // `Expires` only counts when there is no `max-age` at all (RFC 9111 §5.3), however the
            // `max-age` reads: a response that carries both, `max-age=3600` with the `Expires: 0`
            // a legacy stack adds next to it, is fresh for an hour. A `max-age` that is there and
            // cannot be read is stale on its own account, below.
            let maxAge = maxAgeSeconds(headers: headers["Cache-Control"] ?? [])

            if case .absent = maxAge {
                let expires = headers["Expires"] ?? []

                if !expires.isEmpty {
                    guard let expiresDate = expiresDate(headers: expires), expiresDate >= Date() else {
                        return false
                    }
                }
            }

            switch maxAge {
            case .absent:
                break

            case .invalid:
                return false

            case .seconds(let maxAge):
                // `>= .zero` is implied by `.seconds`: `max-age=0` is a valid, common directive
                // ("cacheable, but revalidate before every reuse") and has to make the entry
                // immediately stale, not skip this check entirely.
                //
                // The age the response had when it was received counts too (RFC 9111 §4.2.3): a
                // CDN that sends `Age: 3500` with `max-age=3600` has 100 seconds left, not 3600.
                //
                // `Double`, not `TimeInterval`. Same type, one fewer Foundation import.
                let age = Double(ageSeconds(headers: headers["Age"] ?? []))

                if cachedData.cachedResponse.date.advanced(by: Double(maxAge) - age) < Date() {
                    return false
                }
            }

            return true
        }

        // MARK: - Private methods, header parsing

        /// Whether the response forbids being served from, or written to, the cache.
        ///
        /// - Note: `no-store` is honoured as of 4.0. It was ignored, and it is the stronger of
        /// the two: `no-cache` allows storing as long as the entry is revalidated before reuse,
        /// while `no-store` forbids writing it down at all. A response carrying it was being
        /// persisted to disk regardless, which for anything with an `Authorization` header or a
        /// session cookie in the body is the exact case the directive exists to prevent.
        ///
        /// Compared lowercased, since cache directives are case insensitive.
        private func containsNoCache(headers: [String]) -> Bool {
            for directive in directives(headers) {
                // Prefix, not equality: `no-cache` may carry a field list, as in
                // `no-cache="Set-Cookie"`, and that form is still a no-cache.
                let directive = directive.lowercased()

                if directive == "no-store" || directive == "no-cache" || directive.hasPrefix("no-cache=") {
                    return true
                }
            }

            return false
        }

        /// `nil` when no `Content-Length` directive is present at all (chunked transfer, most
        /// HTTP/2 responses), distinct from a genuine `Content-Length: 0`.
        private func contentLength(headers: [String]) -> Int? {
            directives(headers)
                .compactMap(Int.init)
                .max()
        }

        /// The earliest `Expires` date across the given values, `nil` when any of them is not a
        /// date.
        ///
        /// The caller reads `nil` as already expired: an `Expires` that cannot be read (`0`, `-1`,
        /// an empty value) is how servers say so, and RFC 9111 §5.3 says to take it that way.
        /// Duplicates give the earliest, the one that makes the entry stale soonest.
        ///
        /// - Important: Must not run through ``directives(_:)``. An HTTP date contains a comma
        /// of its own, right after the day name, so splitting the value on commas tears
        /// `Sun, 06 Nov 1994 08:49:37 GMT` in half: stitching the pieces back together by
        /// remembering the last fragment that failed to parse and prepending it to the next one
        /// is not a fix, since `Expires` is a single date, not a list, and splitting is never
        /// appropriate here.
        private func expiresDate(headers: [String]) -> Date? {
            var earliest: Date?

            for header in headers {
                guard let date = Date(httpDate: header.trimming(where: \.isWhitespace)) else {
                    return nil
                }

                earliest = min(earliest ?? date, date)
            }

            return earliest
        }

        /// What a response says of its `max-age`.
        private enum MaxAge {
            case absent
            /// A `max-age` directive whose value is not a number of seconds.
            case invalid
            case seconds(Int)
        }

        /// The `max-age` across the given directives: the smallest when there are several, and
        /// invalid when any of them is.
        ///
        /// - Note: Matches the directive name exactly. It used `range(of:options:)`, which is a
        /// Foundation member this file has no import for, and which searches anywhere in the
        /// string, so `s-maxage` and any vendor directive ending in `max-age` were read as one.
        private func maxAgeSeconds(headers: [String]) -> MaxAge {
            var result = MaxAge.absent

            for directive in directives(headers) {
                let parts = directive.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)

                guard parts[0].trimming(where: \.isWhitespace).lowercased() == "max-age" else {
                    continue
                }

                guard parts.count == 2, let seconds = Self.deltaSeconds(String(parts[1])) else {
                    return .invalid
                }

                if case .seconds(let current) = result {
                    result = .seconds(min(current, seconds))
                } else {
                    result = .seconds(seconds)
                }
            }

            return result
        }

        /// The greatest `Age` across the given values, `0` for those that are not a number of
        /// seconds: an `Age` that cannot be read is no better a reason to hold an entry fresh than
        /// to drop it, and the freshness directives decide that.
        private func ageSeconds(headers: [String]) -> Int {
            headers
                .compactMap { Self.deltaSeconds($0) }
                .max() ?? 0
        }

        /// What RFC 9111 §1.2.2 calls `delta-seconds`: digits only, optionally in quotes, which a
        /// recipient ought to accept. A value beyond `largestDeltaSeconds` reads as that ceiling
        /// (the RFC says 2^31, this is one second less), which is already more than a cache keeps
        /// anything for.
        private static func deltaSeconds(_ value: String) -> Int? {
            var digits = value.trimming(where: \.isWhitespace)

            if digits.count >= 2, digits.hasPrefix("\""), digits.hasSuffix("\"") {
                digits = String(digits.dropFirst().dropLast())
            }

            guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else {
                return nil
            }

            return min(Int(digits) ?? Self.largestDeltaSeconds, Self.largestDeltaSeconds)
        }

        /// 2^31 - 1, not the RFC's 2^31: a literal of 2^31 does not fit an `Int` where that is 32
        /// bits wide (watchOS on arm64_32), and the package would not build for a watch. One
        /// second short of the RFC's ceiling is still centuries beyond any entry's useful life.
        private static let largestDeltaSeconds = Int(Int32.max)

        /// Flattens header values into individual directives.
        ///
        /// - Note: Trimming goes through the package's own `trimming(where:)`, not
        /// `trimmingCharacters(in: .whitespaces)`: that needs `Foundation.CharacterSet`, which
        /// this file has no import for.
        private func directives(_ headers: [String]) -> some Sequence<String> {
            headers
                .lazy
                .flatMap { $0.split(separator: ";") }
                .flatMap { $0.split(separator: ",") }
                .map { $0.trimming(where: \.isWhitespace) }
        }
    }
}
