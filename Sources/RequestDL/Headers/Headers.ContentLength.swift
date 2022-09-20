import Foundation

extension Headers {

    public struct ContentLength: Request {

        private let bytes: Int

        public init(_ bytes: Int) {
            self.bytes = bytes
        }

        public var body: Never {
            Never.bodyException()
        }
    }
}

extension Headers.ContentLength: PrimitiveRequest {

    func makeObject() -> Headers.Object {
        .init("Content-Length", bytes)
    }
}
