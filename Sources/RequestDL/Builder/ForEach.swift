import Foundation

public struct ForEach<Data: Collection, Content: Request>: Request {

    private let data: Data
    private let map: (Data.Element) -> Content

    public init(_ data: Data, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.map = content
    }

    public var body: Never {
        Never.bodyException()
    }

    public static func makeRequest(_ request: ForEach<Data, Content>, _ context: Context) async {
        for request in request.data.map(request.map) {
            await Content.makeRequest(request, context)
        }
    }
}
