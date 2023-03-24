//
//  File.swift
//
//
//  Created by Brenno on 20/03/23.
//

import Foundation

extension Modifiers {

    public struct Upload<Content: Task>: TaskModifier where Content.Element == AsyncResponse {

        let progress: (Int) -> Void

        public func task(_ task: Content) async throws -> TaskResult<AsyncBytes> {
            let result = try await task.result()

            var body: TaskResult<AsyncBytes>?

            for try await part in result {
                switch part {
                case .upload(let bytes):
                    progress(bytes)
                case .download(let head, let bytes):
                    body = .init(
                        head: head,
                        payload: bytes
                    )
                }
            }

            guard let body else {
                fatalError()
            }

            return body
        }
    }
}

extension Task<AsyncResponse> {

    public func upload(
        _ progress: @escaping (Int) -> Void
    ) -> ModifiedTask<Modifiers.Upload<Self>> {
        modify(Modifiers.Upload(progress: progress))
    }
}
