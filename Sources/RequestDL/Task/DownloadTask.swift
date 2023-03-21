//
//  File.swift
//  
//
//  Created by Brenno on 20/03/23.
//

import Foundation

public struct DownloadTask<Content: Property>: Task {

    private let lengthKey: String?
    private let upload: (Int) -> Void
    private let download: (UInt8, Int?) -> Void
    private let content: Content

    public init(
        _ lengthKey: String? = nil,
        _ progress: @escaping (UInt8, Int?) -> Void,
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
        download: @escaping (UInt8, Int?) -> Void,
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
