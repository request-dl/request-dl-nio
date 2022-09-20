import Foundation

extension Headers {

    public struct Origin: Request {

        private let value: Any

        public init<S: StringProtocol>(_ origin: S) {
            self.value = origin
        }

        public var body: Never {
            Never.bodyException()
        }
    }
}

extension Headers.Origin: PrimitiveRequest {

    func makeObject() -> Headers.Object {
        .init("Origin", value)
    }
}
