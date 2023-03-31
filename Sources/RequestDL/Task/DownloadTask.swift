/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that represents a data task request.

 After constructing your download task, you can use the `result` function to receive the
 temporary URL where the content was saved for you, which is the default behavior on Foundation.
 */
@available(*, deprecated, renamed: "DataTask")
public struct DownloadTask<Content: Property>: Task {

    private let content: Content

    /**
     Initializes a new `DownloadTask` with the specified request.

     - Parameter content: The content of the request.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }
}

@available(*, deprecated, renamed: "DataTask")
extension DownloadTask {

    /**
     Retrieves the result of the download task that encapsulates the location where
     the download was saved.

     - Returns: A `TaskResult` that encapsulates a `URL` representing the location
     where the download was saved.

     - Throws: `Error` if there is any problem during the download.
     */
    public func result() async throws -> TaskResult<URL> {
        let delegate = DelegateProxy()
        let (session, request) = try await Resolve(content).build(delegate)

        defer { session.finishTasksAndInvalidate() }

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

@available(*, deprecated, renamed: "DataTask")
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
                    continuation.resume(throwing: EmptyResultError())
                }
            }

            task.resume()
        }
    }
}
