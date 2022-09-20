import Foundation

public struct Query: Request {

    public typealias Body = Never

    let key: String
    let value: Any

    public init(_ key: String, _ value: Any) {
        self.key = key
        self.value = "\(value)"
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension Query: PrimitiveRequest {

    class Object: NodeObject {

        let key: String
        let value: String

        init(_ key: String, _ value: Any) {
            self.key = key
            self.value = "\(value)"
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            request.url = request.url?.append([(key, value)])
        }
    }

    func makeObject() -> Object {
        Object(key, value)
    }
}

extension URL {

    func append(_ parameters: [(String, String)]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
        var queryItems = components?.queryItems ?? []

        parameters.forEach {
            queryItems.append(.init(name: $0, value: $1))
        }

        components?.queryItems = queryItems
        return components?.url ?? self
    }
}
