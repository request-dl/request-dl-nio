//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Date
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

        func callAsFunction(_ client: Internals.Client) async -> Output {
            logger?.log(
                level: .debug,
                "Evaluating cache for request",
                additionalMetadata: [
                    "cache_strategy": .stringConvertible(String(describing: requestConfiguration.cacheStrategy))
                ]
            )

            if requestConfiguration.cacheStrategy != .ignoreCachedData {
                if let cachedData = await storedCachedData() {
                    let cachedSessionTask = await checkIfCachedDataStillValid(
                        client: client,
                        cached: cachedData
                    )

                    if let cachedSessionTask {
                        logger?.log(level: .debug, "Cache hit - returning cached session task")
                        return .task(cachedSessionTask)
                    }
                } else if case .useCachedDataOnly = requestConfiguration.cacheStrategy {
                    logger?.log(
                        level: .warning,
                        "No cached data available, but strategy is 'useCachedDataOnly' — returning error"
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

        private func checkIfCachedDataStillValid(
            client: Internals.Client,
            cached cachedData: CachedData
        ) async -> SessionTask? {
            switch requestConfiguration.cacheStrategy {
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
                    download.failed(HTTPClientError.cancelled)
                    download.close()
                },
                response: .init(
                    logger: logger,
                    uploadingBytes: .zero,
                    upload: .empty(),
                    head: .constant(cachedData.cachedResponse.response),
                    download: download.stream
                )
            )
        }

        private func validateCachedData(
            client: Internals.Client,
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
                cachedData.cachedResponse.response.headers,
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
            client: Internals.Client,
            cached cachedData: CachedData
        ) async -> HTTPHeaders? {
            var requestConfiguration = requestConfiguration
            requestConfiguration.method = "HEAD"

            // Conditional request headers. Copying `ETag` and `Last-Modified` straight onto the
            // request tells the server nothing: those are response headers. A server only
            // answers 304 when it is asked with `If-None-Match` or `If-Modified-Since` — without
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
                let response = try? await client.execute(
                    request: requestConfiguration.build(eventLoop: client.eventLoopGroup.any()),
                    logger: logger
                ).response()
            else { return nil }

            if response.status.code == 304 {
                logger?.log(level: .info, "Cache validated (304 Not Modified) — reusing cached data")
                return cachedData.response.headers
            }

            // Both sides defaulted before comparing. `response.headers[name]` is optional and
            // the cached side had `?? []` applied, so a server that sends neither header
            // compared `nil` against `[]`, which is not equal, and every such response
            // invalidated a cache entry that was in fact unchanged.
            for name in ["Last-Modified", "ETag"] {
                let fresh = response.headers[name]
                let cached = cachedData.response.headers[name] ?? []

                guard fresh == cached else {
                    logger?.log(
                        level: .info,
                        "Cache invalidated (status: \(response.status.code)) — will fetch fresh data"
                    )
                    return nil
                }
            }

            return .init(response.headers)
        }

        /// Sets a conditional request header from the values the cached response carries.
        private func setConditionalHeader(
            _ headers: inout HTTPHeaders,
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
        /// `cachedHeaders` parameter of a helper that prefers whatever was already there — that
        /// could only ever add a directive that was missing and never refresh one that existed,
        /// and picking up a fresher `max-age` is the entire point of revalidating.
        private func updateCacheHeaders(
            _ cachedHeaders: HTTPHeaders,
            with newHeaders: HTTPHeaders
        ) -> HTTPHeaders {
            var merged = cachedHeaders

            replaceHeader(&merged, with: newHeaders, for: "Cache-Control")
            replaceHeader(&merged, with: newHeaders, for: "Expires")

            return merged
        }

        private func replaceHeader(
            _ headers: inout HTTPHeaders,
            with newHeaders: HTTPHeaders,
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
            with updatedHeaders: HTTPHeaders
        ) -> CachedResponse {
            .init(
                response: .init(
                    url: cachedResponse.response.url,
                    status: cachedResponse.response.status,
                    version: cachedResponse.response.version,
                    headers: updatedHeaders,
                    isKeepAlive: cachedResponse.response.isKeepAlive
                ),
                policy: cachedResponse.policy
            )
        }

        private func cacheIfNeeded(
            dataCache: DataCache,
            requestConfiguration: RequestConfiguration
        ) async throws -> (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)? {
            guard requestConfiguration.isCacheEnabled else {
                return nil
            }

            return { head -> Internals.AsyncStream<Internals.DataBuffer>? in
                guard !containsNoCache(headers: head.headers["Cache-Control"] ?? []) else {
                    return nil
                }

                let contentLength = contentLength(headers: head.headers["Content-Length"] ?? [])

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

                        logger?.log(
                            level: .debug,
                            "Cached response saved",
                            additionalMetadata: [
                                "size_bytes": .stringConvertible(cacheBuffer.readableBytes)
                            ]
                        )
                    } catch {
                        logger?.log(level: .error, "Failed to cache response: \(error.localizedDescription)")
                        await dataCache.remove(forKey: requestConfiguration.url)
                    }
                }

                return asyncBuffers
            }
        }

        private func isCachedDataValid(_ cachedData: CachedData) -> Bool {
            let headers = cachedData.response.headers

            let contentLength = contentLength(headers: headers["Content-Length"] ?? [])

            if cachedData.buffer.readableBytes != contentLength {
                return false
            }

            if let expiresDate = expiresDate(headers: headers["Expires"] ?? []) {
                if expiresDate < Date() {
                    return false
                }
            }

            if let maxAge = maxAgeSeconds(headers: headers["Cache-Control"] ?? []) {
                // `Double`, not `TimeInterval`. Same type, one fewer Foundation import.
                if maxAge > .zero, cachedData.cachedResponse.date.advanced(by: Double(maxAge)) < Date() {
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

        private func contentLength(headers: [String]) -> Int {
            directives(headers)
                .compactMap(Int.init)
                .max() ?? .zero
        }

        /// The latest `Expires` date across the given values.
        ///
        /// - Important: Must not run through ``directives(_:)``. An HTTP date contains a comma
        /// of its own, right after the day name, so splitting the value on commas tears
        /// `Sun, 06 Nov 1994 08:49:37 GMT` in half — stitching the pieces back together by
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
        /// `trimmingCharacters(in: .whitespaces)` — that needs `Foundation.CharacterSet`, which
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
