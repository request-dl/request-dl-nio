import Foundation

@available(iOS 15, tvOS 15, watchOS 15, macOS 12, *)
public struct BytesTask<Content: Request>: Task {

    private let content: Content

    public init(@RequestBuilder content: () -> Content) {
        self.content = content()
    }
}

@available(iOS 15, tvOS 15, watchOS 15, macOS 12, *)
extension BytesTask {

    public func response() async throws -> TaskResult<URLSession.AsyncBytes> {
        let delegate = DelegateProxy()
        let (session, request) = await Resolver(content).make(delegate)

        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.bytes(for: request, delegate: delegate)
        return .init(response: response, data: data)
    }
}
