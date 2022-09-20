import Foundation

extension Headers {

    public struct Referer: Request {

        private let value: Any

        public init<S: StringProtocol>(_ url: S) {
            self.value = url
        }

        public var body: Never {
            Never.bodyException()
        }
    }
}

extension Headers.Referer: PrimitiveRequest {

    func makeObject() -> Headers.Object {
        .init("Referer", value)
    }
}
