//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#endif

extension Internals {

    struct CacheControl: Sendable {

        enum Output {
            case task(SessionTask)
            case cache((@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?)
        }

        // MARK: - Internal properties

        let requestConfiguration: RequestConfiguration
        let dataCache: DataCache
        let logger: Internals.TaskLogger?

        // MARK: - Internal methods

        func callAsFunction(_ client: any RequestExecutingClient) async -> Output {
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
                        cached: cachedData
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
                )
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
                    head: .throwing(EmptyCachedDataError()),
                    download: .empty()
                )
            )
        }

        private func storedCachedData() async -> CachedData? {
            guard requestConfiguration.isCacheEnabled else {
                return nil
            }

            return await dataCache.getCachedData(
                forKey: requestConfiguration.url,
                policy: requestConfiguration.cachePolicy
            )
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

        /// Whether the outgoing request carries an `Authorization` header.
        ///
        /// `DataCache` keys entries by URL alone, and is commonly a single, process-wide store
        /// (`DataCache.shared`). Without this check, an app where more than one account can be
        /// signed in over the app's lifetime (sign out, a different user signs in) could serve
        /// one account's cached, authenticated response to another: nothing here folds the
        /// request's own credentials into the cache key, or a `Vary` response header, the way a
        /// browser's shared cache would.
        private var requestCarriesCredentials: Bool {
            !(requestConfiguration.headers["Authorization"] ?? []).isEmpty
        }

        /// Whether the response's own `Cache-Control` explicitly permits a cache to store a
        /// response to a credentialed (`Authorization`-bearing) request, per RFC 7234 §3.2:
        /// `must-revalidate`, `public`, or `s-maxage` are the only directives the RFC recognizes
        /// as having that effect. Absent one of these, storing at all is what the RFC forbids —
        /// unlike `no-store`/`no-cache`, there is no directive that must be *present* to trigger
        /// this; the request having `Authorization` at all is what does.
        private func permitsCachingCredentialedResponse(headers: [String]) -> Bool {
            for directive in directives(headers) {
                let directive = directive.lowercased()

                if directive == "public" || directive == "must-revalidate" || directive.hasPrefix("s-maxage=") {
                    return true
                }
            }

            return false
        }

        private func checkIfCachedDataStillValid(
            client: any RequestExecutingClient,
            cached cachedData: CachedData
        ) async -> SessionTask? {
            switch effectiveCacheStrategy {
            case .ignoreCachedData:
                return nil

            case .useCachedDataOnly:
                return await makeCachedSession(cachedData) ?? emptyCachedDataTask()

            case .returnCachedDataElseLoad:
                return await makeCachedSession(cachedData)

            case .reloadAndValidateCachedData:
                guard
                    let cachedData = await validateCachedData(
                        client: client,
                        dataCache: dataCache,
                        cached: cachedData,
                        requestConfiguration: requestConfiguration
                    )
                else { return nil }

                return await makeCachedSession(cachedData)
            }
        }

        private func makeCachedSession(_ cachedData: CachedData) async -> SessionTask? {
            if !isCachedDataValid(cachedData) {
                await dataCache.remove(forKey: requestConfiguration.url)
                return nil
            }

            let download = await Internals.DownloadBuffer(
                readingMode: requestConfiguration.readingMode
            )

            _Concurrency.Task(priority: .background) {
                let download = download
                download.append(cachedData.buffer)
                download.close()
            }

            return SessionTask(
                seed: .init {
                    download.failed(Internals.TaskCancelledError())
                    download.close()
                },
                response: .init(
                    logger: logger,
                    uploadingBytes: .zero,
                    upload: .empty(),
                    decompressionDispatch: .skip,
                    head: .constant(cachedData.cachedResponse.response),
                    download: download.stream
                )
            )
        }

        private func validateCachedData(
            client: any RequestExecutingClient,
            dataCache: DataCache,
            cached cachedData: CachedData,
            requestConfiguration: RequestConfiguration
        ) async -> CachedData? {
            guard
                let headers = await getUpdatedHeadersForCache(
                    client: client,
                    cached: cachedData
                )
            else { return nil }

            let modifiedHeaders = updateCacheHeaders(
                RequestDL.HTTPHeaders(cachedData.cachedResponse.response.headers.map { ($0.name, $0.value) }),
                with: headers
            )

            guard modifiedHeaders != cachedData.response.headers else {
                return cachedData
            }

            let cachedResponse = updateCachedResponse(
                cachedData.cachedResponse,
                with: modifiedHeaders
            )

            await dataCache.updateCached(
                key: requestConfiguration.url,
                cachedResponse: cachedResponse
            )

            return await dataCache.getCachedData(
                forKey: requestConfiguration.url,
                policy: requestConfiguration.cachePolicy
            )
        }

        private func getUpdatedHeadersForCache(
            client: any RequestExecutingClient,
            cached cachedData: CachedData
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
                    logger: logger
                )
            else { return nil }

            if head.status.code == 304 {
                logger?.log(level: .info, "Cache validated (304 Not Modified), reusing cached data")
                return cachedData.response.headers
            }

            // Both sides defaulted before comparing. `response.headers[name]` is optional and
            // the cached side had `?? []` applied, so a server that sends neither header
            // compared `nil` against `[]`, which is not equal, and every such response
            // invalidated a cache entry that was in fact unchanged.
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
                policy: cachedResponse.policy
            )
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
        ) async throws -> (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)? {
            guard requestConfiguration.isCacheEnabled else {
                return nil
            }

            return { head -> Internals.AsyncStream<Internals.DataBuffer>? in
                let headHeaders = RequestDL.HTTPHeaders(head.headers.map { ($0.name, $0.value) })

                guard
                    Self.isCacheableByDefault(statusCode: head.status.code),
                    !containsNoCache(headers: headHeaders["Cache-Control"] ?? []),
                    !requestForbidsStoring,
                    !requestCarriesCredentials
                        || permitsCachingCredentialedResponse(headers: headHeaders["Cache-Control"] ?? [])
                else {
                    return nil
                }

                // A capacity hint for the allocation below, not a correctness check, so `0` is a
                // fine stand-in when the header is absent.
                let contentLength = contentLength(headers: headHeaders["Content-Length"] ?? []) ?? 0

                // Read exactly once, by the task below. Buffering until that read begins
                // covers the hop it takes to get going, and from then on only the gap between
                // the download and the disk writer stays in memory.
                let asyncBuffers = Internals.AsyncStream<Internals.DataBuffer>(
                    bufferingPolicy: .untilFirstIteration
                )

                dataCache.trackWrite {
                    // On every exit path. Without it, a task that gives up before reaching the
                    // loop leaves behind a stream nobody will ever drain, and the download goes
                    // on feeding it for the rest of the response. Closing makes every later
                    // append a no op, so the producer stops buffering without having to know
                    // that its reader is gone.
                    defer { asyncBuffers.close() }

                    guard
                        var cacheBuffer = await dataCache.allocateBuffer(
                            key: requestConfiguration.url,
                            cachedResponse: .init(
                                response: head,
                                policy: requestConfiguration.cachePolicy
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
                        for try await buffer in asyncBuffers {
                            // By value, not `inout`. This is `DataCache.Buffer.writeBuffer`,
                            // which reads through `getBytes()` and leaves the argument's cursor
                            // alone, not the draining `Internals.Buffer.writeBuffer(_:)`.
                            await cacheBuffer.writeBuffer(buffer)
                        }

                        // Corrects the usage estimate `allocateBuffer` above set from
                        // `contentLength` (a pre-write hint, `0` for chunked/unknown-length
                        // responses) to the real byte count now that it's known. See
                        // `DataCache.finalizeWrite(_:contentLengthHint:)`.
                        dataCache.finalizeWrite(cacheBuffer, contentLengthHint: Int64(contentLength))

                        logger?.log(
                            level: .debug,
                            "Cached response saved",
                            additionalMetadata: [
                                "size_bytes": .stringConvertible(cacheBuffer.readableBytes)
                            ]
                        )
                    } catch {
                        logger?.log(level: .error, "Failed to cache response: \(String(describing: error))")
                        await dataCache.discardFailedWrite(cacheBuffer, forKey: requestConfiguration.url)
                    }
                }

                return asyncBuffers
            }
        }

        private func isCachedDataValid(_ cachedData: CachedData) -> Bool {
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
            if let contentLength = contentLength(headers: headers["Content-Length"] ?? []),
                (headers["Content-Encoding"] ?? []).isEmpty,
                cachedData.buffer.readableBytes != contentLength
            {
                return false
            }

            if let expiresDate = expiresDate(headers: headers["Expires"] ?? []) {
                if expiresDate < Date() {
                    return false
                }
            }

            if let maxAge = maxAgeSeconds(headers: headers["Cache-Control"] ?? []) {
                // `>= .zero`, not `> .zero`: `max-age=0` is a valid, common directive ("cacheable,
                // but revalidate before every reuse") and must make the entry immediately stale,
                // not skip this check entirely. A negative value is malformed and still ignored,
                // same as before.
                //
                // `Double`, not `TimeInterval`. Same type, one fewer Foundation import.
                if maxAge >= .zero, cachedData.cachedResponse.date.advanced(by: Double(maxAge)) < Date() {
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

        /// The latest `Expires` date across the given values.
        ///
        /// - Important: Must not run through ``directives(_:)``. An HTTP date contains a comma
        /// of its own, right after the day name, so splitting the value on commas tears
        /// `Sun, 06 Nov 1994 08:49:37 GMT` in half: stitching the pieces back together by
        /// remembering the last fragment that failed to parse and prepending it to the next one
        /// is not a fix, since `Expires` is a single date, not a list, and splitting is never
        /// appropriate here.
        private func expiresDate(headers: [String]) -> Date? {
            headers
                .compactMap { Date(httpDate: $0.trimming(where: \.isWhitespace)) }
                .max()
        }

        /// The largest `max-age` across the given directives.
        ///
        /// - Note: Matches the directive name exactly. It used `range(of:options:)`, which is a
        /// Foundation member this file has no import for, and which searches anywhere in the
        /// string, so `s-maxage` and any vendor directive ending in `max-age` were read as one.
        private func maxAgeSeconds(headers: [String]) -> Int? {
            directives(headers)
                .compactMap { directive -> Int? in
                    let parts = directive.split(separator: "=", maxSplits: 1)

                    guard
                        parts.count == 2,
                        parts[0].trimming(where: \.isWhitespace).lowercased() == "max-age"
                    else { return nil }

                    return Int(parts[1].trimming(where: \.isWhitespace))
                }
                .max()
        }

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
