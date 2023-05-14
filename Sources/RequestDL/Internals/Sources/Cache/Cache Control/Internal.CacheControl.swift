/*
 See LICENSE for this package's licensing information.
*/

import Foundation

// TODO: - Verify cache expiration using headers

// TODO: - Lock cache while is writing
// block attempt to write over current process

// TODO: - Return cache only if it was totally wrote

// TODO: - Unit tests for cache

// TODO: - cache responses with zero bytes
// cache responses with zero bytes

extension Internals {

    struct CacheControl: Sendable {

        enum Output {
            case task(SessionTask)
            case cache(((Internals.ResponseHead) -> Internals.DataStream<Internals.DataBuffer>?)?)
        }

        let request: Internals.Request
        let dataCache: DataCache

        func callAsFunction(_ client: Internals.Client) async -> Output {
            if let cachedData = storedCachedData() {
                let cachedSessionTask = await checkIfCachedDataStillValid(
                    client: client,
                    cached: cachedData
                )

                if let cachedSessionTask {
                    return .task(cachedSessionTask)
                }
            }

            return .cache(try? await cacheIfNeeded(
                dataCache: dataCache,
                request: request
            ))
        }

        private func storedCachedData() -> CachedData? {
            guard request.isCacheEnabled else {
                return nil
            }

            return dataCache.getCachedData(forKey: request.url)
        }

        private func checkIfCachedDataStillValid(
            client: Internals.Client,
            cached cachedData: CachedData
        ) async -> SessionTask? {
            switch request.localCacheStrategy {
            case .ignoresStored:
                return nil
            case .usesStoredOnly:
                return makeCachedSession(cachedData)
            case .returnStoredElseLoad:
                guard let cachedData = await validateCachedData(
                    client: client,
                    dataCache: dataCache,
                    cached: cachedData,
                    request: request
                ) else { return nil }

                return makeCachedSession(cachedData)
            }
        }

        private func makeCachedSession(_ cachedData: CachedData) -> SessionTask {
            let download = Internals.DownloadBuffer(
                readingMode: request.readingMode
            )

            _Concurrency.Task(priority: .background) {
                var download = download
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
            guard let headers = await getUpdatedHeadersForCache(client) else {
                return nil
            }

            let modifiedHeaders = updateCacheHeaders(
                cachedData.cachedResponse.response.headers,
                with: headers
            )

            let cachedResponse = updateCachedResponse(
                cachedData.cachedResponse,
                with: modifiedHeaders
            )

            dataCache.updateCached(
                key: request.url,
                cachedResponse: cachedResponse
            )

            return .init(
                cachedResponse: cachedResponse,
                buffer: cachedData.buffer
            )
        }

        private func getUpdatedHeadersForCache(_ client: Internals.Client) async -> Internals.Headers? {
            var request = request
            request.method = "HEAD"

            guard let response = try? await client.execute(request: request.build()).get() else {
                return nil
            }

            if response.status.code != 304 {
                dataCache.remove(forKey: request.url)
                return nil
            }

            return Internals.Headers(response.headers)
        }

        private func updateCacheHeaders(
            _ cachedHeaders: Internals.Headers,
            with newHeaders: Internals.Headers
        ) -> Internals.Headers {
            var cachedHeaders = cachedHeaders

            let lastModified = newHeaders.getValue(forKey: "Last-Modified")
            let eTag = newHeaders.getValue(forKey: "ETag")

            let isLastModifiedUpdated = cachedHeaders.getValue(forKey: "Last-Modified").map {
                $0 != lastModified
            } ?? false

            let isETagUpdated = cachedHeaders.getValue(forKey: "ETag").map {
                $0 != eTag
            } ?? false

            guard isLastModifiedUpdated || isETagUpdated else {
                return cachedHeaders
            }

            if isLastModifiedUpdated, let lastModified {
                cachedHeaders.setValue(lastModified, forKey: "Last-Modified")
            }

            if isETagUpdated, let eTag {
                cachedHeaders.setValue(eTag, forKey: "ETag")
            }

            if let cacheControl = newHeaders.getValue(forKey: "Cache-Control") {
                cachedHeaders.setValue(cacheControl, forKey: "Cache-Control")
            }

            return cachedHeaders
        }

        private func updateCachedResponse(
            _ cachedResponse: CachedResponse,
            with updatedHeaders: Internals.Headers
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
        ) async throws -> ((Internals.ResponseHead) -> Internals.DataStream<Internals.DataBuffer>?)? {
            guard request.isCacheEnabled else {
                return nil
            }

            return { head -> Internals.DataStream<Internals.DataBuffer>? in
                // TODO: - Accepts nil as zero
                guard
                    let contentLengthValue = head.headers.getValue(forKey: "Content-Length"),
                    let contentLength = contentLengthValue.getHeaderContentLength()
                else { return nil }

                // TODO: - Needs optimizations
                let stream = Internals.DataStream<Internals.DataBuffer>()

                _Concurrency.Task(priority: .background) {
                    guard var buffer = dataCache.allocateBuffer(
                        key: request.url,
                        cachedResponse: .init(
                            response: head,
                            policy: request.cachePolicy
                        ),
                        contentLength: UInt64(contentLength)
                    ) else { return }

                    do {
                        for try await dataBuffer in stream.asyncStream() {
                            buffer.writeBuffer(dataBuffer)
                        }
                    } catch {
                        dataCache.remove(forKey: request.url)
                    }
                }

                return stream
            }
        }
    }
}

extension String {

    fileprivate func getHeaderContentLength() -> Int? {
        split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { Int($0) != nil })
            .flatMap(Int.init)
    }
}
