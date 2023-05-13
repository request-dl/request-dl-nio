/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct RawTask<Content: Property>: Task {

    let content: Content
}

extension RawTask {

    func result() async throws -> AsyncResponse {
        let (session, request) = try await Resolve(content).build()
        return try await .init(session.request(request).response)
    }
}
