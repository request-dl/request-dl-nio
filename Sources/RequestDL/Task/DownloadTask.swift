/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct DownloadTask<Content: Property>: Task {

    private let lengthKey: String?
    private let upload: (Int) -> Void
    private let download: (Data, Int?) -> Void
    private let content: Content

    public init(
        _ lengthKey: String? = nil,
        _ progress: @escaping (Data, Int?) -> Void,
        @PropertyBuilder content: () -> Content
    ) {
        self.init(
            lengthKey,
            upload: { _ in },
            download: progress,
            content: content
        )
    }

    public init(
        _ lengthKey: String? = nil,
        upload: @escaping (Int) -> Void,
        download: @escaping (Data, Int?) -> Void,
        @PropertyBuilder content: () -> Content
    ) {
        self.lengthKey = lengthKey
        self.upload = upload
        self.download = download
        self.content = content()
    }

    public func result() async throws -> TaskResult<Data> {
        try await RawTask(content)
            .upload(upload)
            .download(lengthKey, download)
            .result()
    }
}
