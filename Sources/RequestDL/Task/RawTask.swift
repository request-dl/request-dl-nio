/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct RawTask<Content: Property>: Task {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    func result() async throws -> AsyncResponse {
        let (session, request) = try await Resolver(content).make()
        return try await .init(session.request(request).response)
    }
}
