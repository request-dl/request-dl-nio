import Foundation

extension Headers {

    public struct Host: Request {

        private let value: Any

        public init<Host, Port>(
            _ host: Host,
            port: Port
        ) where Host: StringProtocol, Port: StringProtocol {
            self.value = "\(host)\(port)"
        }

        public init<S: StringProtocol>(_ host: S) {
            self.value = host
        }

        public var body: Never {
            Never.bodyException()
        }
    }
}

extension Headers.Host: PrimitiveRequest {

    func makeObject() -> Headers.Object {
        .init("Host", value)
    }
}
