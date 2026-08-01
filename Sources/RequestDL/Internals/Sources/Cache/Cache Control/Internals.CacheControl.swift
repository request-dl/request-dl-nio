//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
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
                if let cachedData = storedCachedData() {
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
                    return .task(
                        SessionTask(
                            Internals.AsyncResponse(
                                logger: logger,
                                uploadingBytes: .zero,
                                upload: .empty(),
                                head: .throwing(EmptyCachedDataError()),
                                download: .empty()
                            )
                        )
                    )
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

        private func storedCachedData() -> CachedData? {
            guard requestConfiguration.isCacheEnabled else {
                return nil
            }

            return dataCache.getCachedData(
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
                return makeCachedSession(cachedData)
                    ?? {
                        SessionTask(
                            AsyncResponse(
                                logger: logger,
                                uploadingBytes: .zero,
                                upload: .empty(),
                                head: .throwing(EmptyCachedDataError()),
                                download: .empty()
                            )
                        )
                    }()
            case .returnCachedDataElseLoad:
                return makeCachedSession(cachedData)
            case .reloadAndValidateCachedData:
                guard
                    let cachedData = await validateCachedData(
                        client: client,
                        dataCache: dataCache,
                        cached: cachedData,
                        requestConfiguration: requestConfiguration
                    )
                else { return nil }

                return makeCachedSession(cachedData)
            }
        }

        private func makeCachedSession(_ cachedData: CachedData) -> SessionTask? {
            if !isCachedDataValid(cachedData) {
                dataCache.remove(forKey: requestConfiguration.url)
                return nil
            }

            let download = Internals.DownloadBuffer(
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

            dataCache.updateCached(
                key: requestConfiguration.url,
                cachedResponse: cachedResponse
            )

            return dataCache.getCachedData(
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
            // request, which is what this used to do, tells the server nothing: those are
            // response headers. A server only answers 304 when it is asked with `If-None-Match`
            // or `If-Modified-Since`, so without these the 304 branch below was unreachable and
            // every revalidation downloaded the whole body again.
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
                    request: requestConfiguration.build(),
                    logger: logger
                ).response()
            else { return nil }

            if response.status.code == 304 {
                logger?.log(level: .info, "Cache validated (304 Not Modified) — reusing cached data")
                return cachedData.response.headers
            }

            let lastModified = response.headers["Last-Modified"]
            let eTag = response.headers["ETag"]

            if lastModified != cachedData.response.headers["Last-Modified"] ?? [] {
                logger?.log(level: .info, "Cache invalidated (status: \(response.status.code)) — will fetch fresh data")
                return nil
            }

            if eTag != cachedData.response.headers["ETag"] ?? [] {
                logger?.log(level: .info, "Cache invalidated (status: \(response.status.code)) — will fetch fresh data")
                return nil
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
        /// The new value has to win. The previous version passed the new headers through the
        /// `cachedHeaders` parameter of a helper that preferred whatever was already there, so
        /// it could only ever add a directive that was missing and never refresh one that
        /// existed. Picking up a fresher `max-age` is the entire point of revalidating.
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
                        var cacheBuffer = dataCache.allocateBuffer(
                            key: requestConfiguration.url,
                            cachedResponse: .init(
                                response: head,
                                policy: requestConfiguration.cachePolicy
                            ),
                            contentLength: UInt64(contentLength)
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
                            cacheBuffer.writeBuffer(buffer)
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
                        dataCache.remove(forKey: requestConfiguration.url)
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
                if maxAge > .zero && cachedData.cachedResponse.date.advanced(by: TimeInterval(maxAge)) < Date() {
                    return false
                }
            }

            return true
        }

        private func containsNoCache(headers: [String]) -> Bool {
            flatAndCombineHeadersValues(headers)
                .contains("no-cache")
        }

        private func contentLength(headers: [String]) -> Int {
            flatAndCombineHeadersValues(headers)
                .compactMap(Int.init)
                .max() ?? .zero
        }

        private func expiresDate(headers: [String]) -> Date? {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            dateFormatter.timeZone = TimeZone(identifier: "GMT")

            var _weekday: String?
            var dates: [Date] = []

            for part in flatAndCombineHeadersValues(headers) {
                if let weekday = _weekday {
                    let literalDate = weekday + ", \(part)"

                    if let date = dateFormatter.date(from: literalDate) {
                        dates.append(date)
                        _weekday = nil
                    } else {
                        _weekday = part
                    }
                } else {
                    _weekday = part
                }
            }

            return dates.max()
        }

        private func maxAgeSeconds(headers: [String]) -> Int? {
            flatAndCombineHeadersValues(headers)
                .compactMap {
                    let components = $0.split(separator: "=")

                    if components.count <= 1 {
                        return nil
                    }

                    if components[0].range(of: "max-age", options: [.caseInsensitive]) == nil {
                        return nil
                    }

                    return Int(components.dropFirst().joined(separator: "="))
                }
                .max()
        }

        private func flatAndCombineHeadersValues(_ headers: [String]) -> LazyMapSequence<[Substring], String> {
            headers.reduce([]) { $0 + $1.split(separator: ";") }
                .reduce([]) { $0 + $1.split(separator: ",") }
                .lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
}
