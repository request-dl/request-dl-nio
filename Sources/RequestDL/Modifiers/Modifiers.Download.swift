//
//  File.swift
//  
//
//  Created by Brenno on 20/03/23.
//

import Foundation

extension Modifiers {

    public struct Download<Content: Task>: TaskModifier where Content.Element == TaskResult<AsyncBytes> {

        public typealias Element = Data

        let contentLengthKey: String?
        let progress: (UInt8, Int?) -> Void

        public func task(_ task: Content) async throws -> Element {
            let result = try await task.result()

            let contentLenght = contentLengthKey
                .flatMap { result.head.headers[$0] }
                .flatMap(Int.init)

            var data = Data()

            for try await byte in result.payload {
                data.append(byte)
                progress(byte, contentLenght)
            }

            return data
        }
    }
}

extension Task<TaskResult<AsyncBytes>> {

    public func download(
        _ contentLengthKey: String? = "content-length",
        progress: @escaping (UInt8, Int?) -> Void
    ) -> ModifiedTask<Modifiers.Download<Self>> {
        modify(Modifiers.Download(
            contentLengthKey: contentLengthKey,
            progress: progress
        ))
    }
}
