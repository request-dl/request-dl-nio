import Foundation

public struct QueryGroup<Content: Request>: Request {

    public typealias Body = Never

    let parameter: Content

    public init(@RequestBuilder parameter: () -> Content) {
        self.parameter = parameter()
    }

    public var body: Never {
        Never.bodyException()
    }

    public static func makeRequest(_ request: QueryGroup<Content>, _ context: Context) async {
        let node = Node(
            root: context.root,
            object: EmptyObject(request),
            children: []
        )

        let newContext = Context(node)
        await Content.makeRequest(request.parameter, newContext)

        let parameters = newContext.findCollection(Query.Object.self).map {
            ($0.key, $0.value)
        }

        context.append(Node(
            root: context.root,
            object: Object(parameters),
            children: []
        ))
    }
}

extension QueryGroup where Content == ForEach<[String: Any], Query> {

    public init(_ dictionary: [String: Any]) {
        self.init {
            ForEach(dictionary) {
                Query($0.key, $0.value)
            }
        }
    }
}

extension QueryGroup {

    struct Object: NodeObject {

        private let parameters: [(String, String)]

        init(_ parameters: [(String, String)]) {
            self.parameters = parameters
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            request.url = request.url?.append(parameters)
        }
    }
}
