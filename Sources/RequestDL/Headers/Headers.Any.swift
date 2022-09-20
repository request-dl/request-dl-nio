import Foundation

extension Headers {

    public struct `Any`: Request {

        let key: String
        let value: Any

        public init<S: StringProtocol>(key: S, value: Any) {
            self.key = "\(key)"
            self.value = value
        }

        public var body: Never {
            Never.bodyException()
        }
    }
}

extension Headers.`Any`: PrimitiveRequest {

    func makeObject() -> Headers.Object {
        .init(key, value)
    }
}
