/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct DownloadTask<Content: Property>: Task {

    private let content: Content

    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }
}

extension DownloadTask {

    public func result() async throws -> TaskResult<AsyncBytes> {
        try await RawTask(content: content)
            .ignoresUploadProgress()
            .result()
    }
}
