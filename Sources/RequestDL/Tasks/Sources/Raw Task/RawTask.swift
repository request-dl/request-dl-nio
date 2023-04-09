/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct RawTask<Content: Property>: Task {

    private let content: Content

    init(content: Content) {
        self.content = content
    }
}

extension RawTask {

    func result() async throws -> AsyncResponse {
        let (session, request) = try await Resolve(content).build()
        return try await .init(session.request(request).response)
    }
}
