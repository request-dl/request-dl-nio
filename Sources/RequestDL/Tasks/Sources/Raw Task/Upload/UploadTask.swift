/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct UploadTask<Content: Property>: Task {

    private let content: Content

    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }
}

extension UploadTask {

    public func result() async throws -> AsyncResponse {
        try await RawTask(content: content).result()
    }
}
