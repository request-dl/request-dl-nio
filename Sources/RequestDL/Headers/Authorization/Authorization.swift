import Foundation

public struct Authorization: Request {

    private let type: TokenType
    private let token: Any

    public init(_ type: TokenType, token: Any) {
        self.type = type
        self.token = token
    }

    public init(username: String, password: String) {
        self.type = .basic
        self.token = {
            Data("\(username):\(password)".utf8)
                .base64EncodedString()
        }()
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension Authorization: PrimitiveRequest {

    struct Object: NodeObject {
        let type: TokenType
        let token: Any

        init(_ type: TokenType, token: Any) {
            self.type = type
            self.token = token
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            request.setValue("\(type.rawValue) \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    func makeObject() -> Object {
        .init(type, token: token)
    }
}
