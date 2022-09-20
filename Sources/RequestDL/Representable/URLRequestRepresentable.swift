import Foundation

public protocol URLRequestRepresentable: Request where Body == Never {

    func updateRequest(_ request: inout URLRequest)
}

extension URLRequestRepresentable {

    public var body: Body {
        Never.bodyException()
    }

    public static func makeRequest(_ request: Self, _ context: Context) async {
        let node = Node(
            root: context.root,
            object: URLRequestRepresentableObject(request.updateRequest(_:)),
            children: []
        )

        context.append(node)
    }
}

struct URLRequestRepresentableObject: NodeObject {

    private let update: (inout URLRequest) -> Void

    init(_ update: @escaping (inout URLRequest) -> Void) {
        self.update = update
    }

    func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
        update(&request)
    }
}
