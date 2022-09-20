import Foundation

extension Headers {

    public struct Accept: Request {

        private let type: RequestDL.ContentType

        public init(_ contentType: RequestDL.ContentType) {
            self.type = contentType
        }

        public var body: Never {
            Never.bodyException()
        }
    }
}

extension Headers.Accept: PrimitiveRequest {

    func makeObject() -> Headers.Object {
        .init("Accept", type.rawValue)
    }
}
