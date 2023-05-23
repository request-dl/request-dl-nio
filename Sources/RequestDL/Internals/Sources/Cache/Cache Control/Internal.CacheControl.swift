/*
 See LICENSE for this package's licensing information.
*/

import Foundation

// swiftlint:disable type_body_length
extension Internals {

    struct CacheControl: Sendable {

        enum Output {
            case task(SessionTask)
            case cache(((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?)
        }

        // MARK: - Internal properties

        let request: Internals.Request
        let dataCache: DataCache

        // MARK: - Internal methods

        func callAsFunction(_ client: Internals.Client) async -> Output {
            if request.cacheStrategy != .ignoreCachedData {
                if let cachedData = storedCachedData() {
                    let cachedSessionTask = await checkIfCachedDataStillValid(
                        client: client,
                        cached: cachedData
                    )

                    if let cachedSessionTask {
                        return .task(cachedSessionTask)
                    }
                }
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
                        upload: .empty(),
                        head: .empty(),
                        download: .throwing(EmptyCachedDataError())
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

            return .init(.init(
                upload: .empty(),
                head: .constant(cachedData.cachedResponse.response),
                download: download.stream
            ))
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

            guard let response = try? await client.execute(request: request.build()).get() else {
                return nil
            }

            let lastModified = response.headers["Last-Modified"]
            let eTag = response.headers["ETag"]

            if lastModified != cachedData.response.headers["Last-Modified"] ?? [] {
                return nil
            }

            if eTag != cachedData.response.headers["ETag"] ?? [] {
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
        ) async throws -> ((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)? {
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
                    } catch {
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

            return flatAndCombineHeadersValues(headers)
                .compactMap(dateFormatter.date(from:))
                .max()
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
// swiftlint:enable type_body_length
