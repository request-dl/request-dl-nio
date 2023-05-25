/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct RawTask<Content: Property>: Task {

    // MARK: - Internal properties

    let content: Content

    // MARK: - Internal methods

    func result() async throws -> AsyncResponse {
        let resolved = try await Resolve(content).build()

        return try await .init(resolved.session.execute(
            request: resolved.request,
            dataCache: resolved.dataCache
        ).response)
    }
}
