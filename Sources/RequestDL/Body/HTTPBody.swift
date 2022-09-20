import Foundation

public struct HTTPBody<Provider: BodyProvider>: Request {

    public typealias Body = Never

    private let provider: Provider

    public init(
        _ dictionary: [String: Any],
        options: JSONSerialization.WritingOptions = .prettyPrinted
    ) where Provider == _DicionaryBody {
        provider = _DicionaryBody(dictionary, options: options)
    }

    public init<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = .init()
    ) where Provider == _EncodableBody<T> {
        provider = _EncodableBody(value, encoder: encoder)
    }

    public init(
        _ string: String,
        using encoding: String.Encoding = .utf8
    ) where Provider == _StringBody {
        provider = _StringBody(string, using: encoding)
    }

    public init(_ data: Data) where Provider == _DataBody {
        provider = _DataBody(data)
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension HTTPBody: PrimitiveRequest {

    struct Object: NodeObject {

        private let provider: Provider

        init(_ provider: Provider) {
            self.provider = provider
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            request.httpBody = provider.data
        }
    }

    func makeObject() -> Object {
        .init(provider)
    }
}
