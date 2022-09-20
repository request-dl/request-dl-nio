import Foundation

extension Never: Request {

    public var body: Never {
        Never.bodyException()
    }
}

extension Never {

    static func bodyException() -> Never {
        fatalError("Body should not be called")
    }
}
