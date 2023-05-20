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
            case cache(((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?)
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

            return dataCache.getCachedData(
                forKey: request.url,
                policy: request.cachePolicy
            )
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

        private func getUpdatedHeadersForCache(_ client: Internals.Client) async -> HTTPHeaders? {
            var request = request
            request.method = "HEAD"

            guard let response = try? await client.execute(request: request.build()).get() else {
                return nil
            }

            if response.status.code != 304 {
                dataCache.remove(forKey: request.url)
                return nil
            }

            return HTTPHeaders(response.headers)
        }

        private func updateCacheHeaders(
            _ cachedHeaders: HTTPHeaders,
            with newHeaders: HTTPHeaders
        ) -> HTTPHeaders {
            var cachedHeaders = cachedHeaders

            let lastModified = newHeaders["Last-Modified"]
            let eTag = newHeaders["ETag"]

            let isLastModifiedUpdated = cachedHeaders["Last-Modified"].map {
                $0 != lastModified
            } ?? false

            let isETagUpdated = cachedHeaders["ETag"].map {
                $0 != eTag
            } ?? false

            guard isLastModifiedUpdated || isETagUpdated else {
                return cachedHeaders
            }

            if isLastModifiedUpdated, let lastModified {
                cachedHeaders.remove(name: "Last-Modified")
                for value in lastModified {
                    cachedHeaders.set(name: "Last-Modified", value: value)
                }
            }

            if isETagUpdated, let eTag {
                cachedHeaders.remove(name: "ETag")
                for value in eTag {
                    cachedHeaders.set(name: "ETag", value: value)
                }
            }

            if let cacheControl = newHeaders["Cache-Control"] {
                cachedHeaders.remove(name: "Cache-Control")
                for value in cacheControl {
                    cachedHeaders.set(name: "Cache-Control", value: value)
                }
            }

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
                // TODO: - Accepts nil as zero
                guard
                    let contentLengthValue = head.headers["Content-Length"],
                    let contentLength = contentLengthValue.getHeaderContentLength()
                else { return nil }

                // TODO: - Needs optimizations
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
    }
}

extension [String] {

    fileprivate func getHeaderContentLength() -> Int? {
        reduce([]) { $0 + $1.split(separator: ";") }
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap(Int.init)
            .first
    }
}
