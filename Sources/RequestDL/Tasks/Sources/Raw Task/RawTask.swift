/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct RawTask<Content: Property>: RequestTask {

    // MARK: - Public properties

    @_spi(Private)
    public var environment = TaskEnvironmentValues()

    // MARK: - Internal properties

    let content: Content

    // MARK: - Internal methods

    func result() async throws -> AsyncResponse {
        let resolved = try await Resolve(content).build()

        let sessionTask = try await resolved.session.execute(
            request: resolved.request,
            dataCache: resolved.dataCache
        )

        return sessionTask()
    }
}
