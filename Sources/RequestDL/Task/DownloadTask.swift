import Foundation
import SwiftUI

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
