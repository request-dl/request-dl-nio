import Foundation

// swiftlint:disable line_length
public struct InterceptedTask<Middleware: MiddlewareType, Content: Task>: Task where Middleware.Element == Content.Element {

    public typealias Element = Content.Element

    let task: Content
    let middleware: Middleware

    init(_ task: Content, _ middleware: Middleware) {
        self.task = task
        self.middleware = middleware
    }
}

extension InterceptedTask {

    public func response() async throws -> Element {
        do {
            let response = try await task.response()
            middleware.received(.success(response))
            return response
        } catch {
            middleware.received(.failure(error))
            throw error
        }
    }
}
