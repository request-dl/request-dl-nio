import Foundation

public struct DataTask<Content: Request>: Task {

    private let content: Content

    public init(@RequestBuilder content: () -> Content) {
        self.content = content()
    }
}

extension DataTask {

    public func response() async throws -> TaskResult<Data> {
        let delegate = DelegateProxy()
        let (session, request) = await Resolver(content).make(delegate)

        defer { session.finishTasksAndInvalidate() }

        if #available(iOS 15, tvOS 15, watchOS 8, macOS 12, *) {
            let (data, response) = try await session.data(for: request, delegate: delegate)
            return .init(response: response, data: data)
        } else {
            return try await oldAPI_response(
                session: session,
                request: request
            )
        }
    }
}

extension DataTask {

    @available(iOS, introduced: 13.0, deprecated: 15.0)
    func oldAPI_response(
        session: URLSession,
        request: URLRequest
    ) async throws -> TaskResult<Data> {
        try await withUnsafeThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let data = data, let response = response {
                    continuation.resume(returning: .init(response: response, data: data))
                } else {
                    continuation.resume(throwing: TaskError.empty)
                }
            }

            task.resume()
        }
    }
}
