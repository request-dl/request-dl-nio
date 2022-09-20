import Foundation

public struct FormValue: Request {

    public typealias Body = Never

    let key: String
    let value: Any

    public init(key: String, value: Any) {
        self.key = key
        self.value = value
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension FormValue: PrimitiveRequest {

    func makeObject() -> FormObject {
        .init(.value(self))
    }
}
