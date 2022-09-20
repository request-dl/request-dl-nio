import Foundation

public struct EmptyRequest: Request {

    public init() {}

    public var body: Never {
        Never.bodyException()
    }
}

extension EmptyRequest: PrimitiveRequest {

    struct Object: NodeObject {

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {}
    }

    func makeObject() -> Object {
        .init()
    }
}
