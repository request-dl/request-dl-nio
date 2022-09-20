import Foundation

public struct OptionalRequest<Content: Request>: Request {

    let content: Content?

    init(_ content: Content?) {
        self.content = content
    }

    public var body: Never {
        Never.bodyException()
    }

    public static func makeRequest(_ request: OptionalRequest<Content>, _ context: Context) async {
        if let content = request.content {
            await Content.makeRequest(content, context)
        }
    }
}
