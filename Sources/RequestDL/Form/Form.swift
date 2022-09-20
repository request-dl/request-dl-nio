import Foundation

struct FormObject: NodeObject {

    let type: FormType

    init(_ type: FormType) {
        self.type = type
    }

    func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
        let boundary = FormUtils.boundary
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormUtils.buildBody([type.data], with: boundary)
    }
}

public struct Form<Content: Request>: Request {

    public typealias Body = Never

    let parameter: Content

    public init(@RequestBuilder parameter: () -> Content) {
        self.parameter = parameter()
    }

    public var body: Never {
        Never.bodyException()
    }

    public static func makeRequest(_ request: Form<Content>, _ context: Context) async {
        let node = Node(
            root: context.root,
            object: EmptyObject(request),
            children: []
        )

        let newContext = Context(node)
        await Content.makeRequest(request.parameter, newContext)

        let parameters = newContext
            .findCollection(FormObject.self)
            .map(\.type)

        context.append(Node(
            root: context.root,
            object: Object(parameters),
            children: []
        ))
    }
}

extension Form {

    struct Object: NodeObject {
        private let types: [FormType]

        init(_ types: [FormType]) {
            self.types = types
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            let boundary = FormUtils.boundary
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = FormUtils.buildBody(types.map(\.data), with: boundary)
        }
    }
}
