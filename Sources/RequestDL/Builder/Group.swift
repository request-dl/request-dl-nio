import Foundation

public struct Group<Content: Request>: Request {

    private let content: Content

    public init(@RequestBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never {
        Never.bodyException()
    }

    public static func makeRequest(_ request: Group<Content>, _ context: Context) async {
        await Content.makeRequest(request.content, context)
    }
}
