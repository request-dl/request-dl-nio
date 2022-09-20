import Foundation

public struct FormData: Request {

    public typealias Body = Never

    let data: Foundation.Data
    let fileName: String
    let key: String?
    let contentType: ContentType

    public init(
        key: String = "",
        name: String,
        type: ContentType,
        data: Foundation.Data
    ) {
        self.key = key.isEmpty ? nil : key
        self.fileName = name
        self.data = data
        self.contentType = type
    }

    public init<T: Encodable>(
        key: String = "",
        _ value: T,
        encoder: JSONEncoder
    ) {
        self.key = key.isEmpty ? nil : key
        self.data = (try? encoder.encode(value)) ?? .init()
        self.fileName = "\(data.count).\(Int.random(in: 0...999))).json"
        self.contentType = .json
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension FormData: PrimitiveRequest {

    func makeObject() -> FormObject {
        .init(.data(self))
    }
}
