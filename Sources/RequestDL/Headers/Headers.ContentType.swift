import Foundation

extension Headers {

    public struct ContentType: Request {

        private let contentType: RequestDL.ContentType

        public init(_ contentType: RequestDL.ContentType) {
            self.contentType = contentType
        }

        public var body: Never {
            Never.bodyException()
        }
    }
}

extension Headers.ContentType: PrimitiveRequest {

    func makeObject() -> Headers.Object {
        .init("Content-Type", contentType.rawValue)
    }
}
