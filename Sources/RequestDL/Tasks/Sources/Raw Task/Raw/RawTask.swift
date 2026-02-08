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

        let logger = Internals.TaskLogger(
            requestConfiguration: resolved.requestConfiguration,
            logger: environment.logger
        )

        let sessionTask = try await resolved.session.execute(
            requestConfiguration: resolved.requestConfiguration,
            dataCache: resolved.dataCache,
            logger: logger
        )

        return sessionTask()
    }
}
