/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct RawTask<Content: Property>: Task {

    let content: Content
}

extension RawTask {

    func result() async throws -> AsyncResponse {
        let resolved = try await Resolve(content).build()

        return try await .init(resolved.session.request(
            resolved.request
        ).response)
    }
}
