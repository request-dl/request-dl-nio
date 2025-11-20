/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct RawTask<Content: Property>: RequestTask {

    // MARK: - Internal properties

    let content: Content

    // MARK: - Internal methods

    func result() async throws -> AsyncResponse {
        let resolved = try await Resolve(
            root: content,
            environment: environment
        ).build()

        #if DEBUG
        environment.logger.debug(
            "Will execute HTTP \(resolved.request.method ?? "GET") request",
            metadata: [
                "host": .string(resolved.request.baseURL),
                "path": .string(resolved.request.pathComponents.isEmpty ? "/" : resolved.request.pathComponents.joinedAsPath()),
                "cache_enabled": .stringConvertible(resolved.request.isCacheEnabled.description),
                "environment": .string(environment.debugDescription)
            ]
        )
        #endif

        let sessionTask = try await resolved.session.execute(
            request: resolved.request,
            dataCache: resolved.dataCache
        )

        return sessionTask()
    }
}
