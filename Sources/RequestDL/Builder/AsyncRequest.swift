import Foundation

public struct AsyncRequest<Content: Request>: Request {

    public typealias Body = Never

    private let content: () async -> Content

    public init(@RequestBuilder content: @escaping () async -> Content) {
        self.content = content
    }

    public var body: Never {
        Never.bodyException()
    }

    public static func makeRequest(_ request: AsyncRequest<Content>, _ context: Context) async {
        await Content.makeRequest(request.content(), context)
    }
}
