//
//  File.swift
//  
//
//  Created by Brenno on 20/03/23.
//

import Foundation

public struct UploadTask<Content: Property>: Task {

    private let progress: (Int) -> Void
    private let content: Content

    public init(
        _ progress: @escaping (Int) -> Void,
        @PropertyBuilder content: () -> Content
    ) {
        self.progress = progress
        self.content = content()
    }

    public func result() async throws -> TaskResult<AsyncBytes> {
        try await RawTask(content)
            .upload(progress)
            .result()
    }
}
