import Foundation

public protocol URLSessionConfigurationRepresentable: Request where Body == Never {

    func updateSessionConfiguration(_ sessionConfiguration: inout URLSessionConfiguration)
}

extension URLSessionConfigurationRepresentable {

    public var body: Body {
        Never.bodyException()
    }

    public static func makeRequest(_ request: Self, _ context: Context) async {
        let node = Node(
            root: context.root,
            object: URLSessionRepresentableObject(request.updateSessionConfiguration(_:)),
            children: []
        )

        context.append(node)
    }
}

struct URLSessionRepresentableObject: NodeObject {

    private let update: (inout URLSessionConfiguration) -> Void

    init(_ update: @escaping (inout URLSessionConfiguration) -> Void) {
        self.update = update
    }

    func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
        update(&configuration)
    }
}
