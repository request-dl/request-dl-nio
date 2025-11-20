/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import Logging

extension Internals {

    struct CacheControl: Sendable {

        enum Output {
            case task(SessionTask)
            case cache((@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?)
        }

        // MARK: - Internal properties

        let request: Internals.Request
        let dataCache: DataCache
        let logger: Logger

        // MARK: - Internal methods

        func callAsFunction(_ client: Internals.Client) async -> Output {
            #if DEBUG
            logger.debug(
                "Evaluating cache for request",
                metadata: [
                    "method": .stringConvertible(request.method ?? "GET"),
                    "host": .string(request.baseURL),
                    "path": .string(request.pathComponents.isEmpty ? "/" : request.pathComponents.joinedAsPath()),
                    "cache_strategy": .stringConvertible(String(describing: request.cacheStrategy))
                ]
            )
            #endif

            if request.cacheStrategy != .ignoreCachedData {
                if let cachedData = storedCachedData() {
                    let cachedSessionTask = await checkIfCachedDataStillValid(
                        client: client,
                        cached: cachedData
                    )

                    if let cachedSessionTask {
                        return .task(cachedSessionTask)
                    }
                } else if case .useCachedDataOnly = request.cacheStrategy {
                    #if DEBUG
                    logger.warning("No cached data available, but strategy is 'useCachedDataOnly' — returning error")
                    #endif
                    return .task(SessionTask(Internals.AsyncResponse(
                        uploadingBytes: .zero,
                        upload: .empty(),
                        head: .throwing(EmptyCachedDataError()),
                        download: .empty()
                    )))
                }
            } else {
                #if DEBUG
                logger.trace("Cache ignored by strategy: ignoreCachedData")
                #endif
            }

            return .cache(try? await cacheIfNeeded(
                dataCache: dataCache,
                request: request
            ))
        }

        // MARK: - Private methods

        private func storedCachedData() -> CachedData? {
            guard request.isCacheEnabled else {
                return nil
            }

            return dataCache.getCachedData(
                forKey: request.url,
                policy: request.cachePolicy
            )
        }

        private func checkIfCachedDataStillValid(
            client: Internals.Client,
            cached cachedData: CachedData
        ) async -> SessionTask? {
            switch request.cacheStrategy {
            case .ignoreCachedData:
                return nil
            case .useCachedDataOnly:
                return makeCachedSession(cachedData) ?? {
                    SessionTask(AsyncResponse(
                        uploadingBytes: .zero,
                        upload: .empty(),
                        head: .throwing(EmptyCachedDataError()),
                        download: .empty()
                    ))
                }()
            case .returnCachedDataElseLoad:
                return makeCachedSession(cachedData)
            case .reloadAndValidateCachedData:
                guard let cachedData = await validateCachedData(
                    client: client,
                    dataCache: dataCache,
                    cached: cachedData,
                    request: request
                ) else { return nil }

                return makeCachedSession(cachedData)
            }
        }

        private func makeCachedSession(_ cachedData: CachedData) -> SessionTask? {
            if !isCachedDataValid(cachedData) {
                dataCache.remove(forKey: request.url)
                return nil
            }

            let download = Internals.DownloadBuffer(
                readingMode: request.readingMode
            )

            _Concurrency.Task(priority: .background) {
                let download = download
                download.append(cachedData.buffer)
                download.close()
            }

            return SessionTask(
                response: .init(
                    uploadingBytes: .zero,
                    upload: .empty(),
                    head: .constant(cachedData.cachedResponse.response),
                    download: download.stream
                ),
                seed: .init {
                    download.failed(HTTPClientError.cancelled)
                    download.close()
                }
            )
        }

        private func validateCachedData(
            client: Internals.Client,
            dataCache: DataCache,
            cached cachedData: CachedData,
            request: Internals.Request
        ) async -> CachedData? {
            guard let headers = await getUpdatedHeadersForCache(
                client: client,
                cached: cachedData
            ) else { return nil }

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
                key: request.url,
                cachedResponse: cachedResponse
            )

            return dataCache.getCachedData(
                forKey: request.url,
                policy: request.cachePolicy
            )
        }

        private func getUpdatedHeadersForCache(
            client: Internals.Client,
            cached cachedData: CachedData
        ) async -> HTTPHeaders? {
            var request = request
            request.method = "HEAD"

            updateHeaders(
                &request.headers,
                cachedHeaders: cachedData.response.headers,
                for: "Last-Modified"
            )

            updateHeaders(
                &request.headers,
                cachedHeaders: cachedData.response.headers,
                for: "ETag"
            )

            guard let response = try? await client.execute(
                request: request.build(),
                logger: logger
            ).response() else { return nil }

            if response.status.code == 304 {
                #if DEBUG
                logger.debug("Cache validated (304 Not Modified) — reusing cached data")
                #endif
                return cachedData.response.headers
            }

            let lastModified = response.headers["Last-Modified"]
            let eTag = response.headers["ETag"]

            if lastModified != cachedData.response.headers["Last-Modified"] ?? [] {
                #if DEBUG
                logger.debug("Cache invalidated (status: \(response.status.code)) — will fetch fresh data")
                #endif
                return nil
            }

            if eTag != cachedData.response.headers["ETag"] ?? [] {
                #if DEBUG
                logger.debug("Cache invalidated (status: \(response.status.code)) — will fetch fresh data")
                #endif
                return nil
            }

            return .init(response.headers)
        }

        private func updateHeaders(
            _ headers: inout HTTPHeaders,
            cachedHeaders: HTTPHeaders,
            for name: String
        ) {
            let values = headers[name] ?? cachedHeaders[name]

            if let values, headers[name] ?? [] != values {
                headers.remove(name: name)

                for value in values {
                    headers.add(name: name, value: value)
                }
            }
        }

        private func updateCacheHeaders(
            _ cachedHeaders: HTTPHeaders,
            with newHeaders: HTTPHeaders
        ) -> HTTPHeaders {
            var cachedHeaders = cachedHeaders

            updateHeaders(
                &cachedHeaders,
                cachedHeaders: newHeaders,
                for: "Cache-Control"
            )

            updateHeaders(
                &cachedHeaders,
                cachedHeaders: newHeaders,
                for: "Expires"
            )

            return cachedHeaders
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
            request: Internals.Request
        ) async throws -> (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)? {
            guard request.isCacheEnabled else {
                return nil
            }

            return { head -> Internals.AsyncStream<Internals.DataBuffer>? in
                guard !containsNoCache(headers: head.headers["Cache-Control"] ?? []) else {
                    return nil
                }

                let contentLength = contentLength(headers: head.headers["Content-Length"] ?? [])

                let asyncBuffers = Internals.AsyncStream<Internals.DataBuffer>()

                _Concurrency.Task(priority: .background) {
                    guard var cacheBuffer = dataCache.allocateBuffer(
                        key: request.url,
                        cachedResponse: .init(
                            response: head,
                            policy: request.cachePolicy
                        ),
                        contentLength: UInt64(contentLength)
                    ) else { return }

                    do {
                        for try await buffer in asyncBuffers {
                            cacheBuffer.writeBuffer(buffer)
                        }
                        #if DEBUG
                        logger.debug("Cached response saved", metadata: [
                            "url": .stringConvertible(request.url),
                            "size_bytes": .stringConvertible(cacheBuffer.readableBytes)
                        ])
                        #endif
                    } catch {
                        #if DEBUG
                        logger.error("Failed to cache response: \(error)")
                        #endif
                        dataCache.remove(forKey: request.url)
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
