//
//  DownloadTask.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

public struct DownloadTask<Content: Request>: Task {

    private let save: (URL) -> Void
    private let content: Content

    public init(
        save: @escaping (URL) -> Void,
        @RequestBuilder content: () -> Content
    ) {
        self.save = save
        self.content = content()
    }
}

extension DownloadTask {

    public func response() async throws -> TaskResult<URL> {
        let delegate = DelegateProxy()
        let (session, request) = await Resolver(content).make(delegate)

        defer { session.finishTasksAndInvalidate() }

        delegate.onDidFinishDownloadingToLocation(save)

        if #available(iOS 15, tvOS 15, watchOS 8, macOS 12, *) {
            let (data, response) = try await session.download(for: request, delegate: delegate)
            return .init(
                response: response,
                data: data
            )
        } else {
            return try await oldAPI_response(
                session: session,
                request: request
            )
        }
    }
}

extension DownloadTask {

    func oldAPI_response(
        session: URLSession,
        request: URLRequest
    ) async throws -> TaskResult<URL> {
        try await withUnsafeThrowingContinuation { continuation in
            let task = session.downloadTask(with: request) { url, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = url, let response = response {
                    continuation.resume(returning: .init(
                        response: response,
                        data: url
                    ))
                } else {
                    continuation.resume(throwing: TaskError.empty)
                }
            }

            task.resume()
        }
    }
}
