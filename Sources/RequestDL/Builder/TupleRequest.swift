import Foundation

public struct TupleRequest<T>: Request {

    private let transformHandler: (Context) async -> Void

    init(transform: @escaping (Context) async -> Void) {
        self.transformHandler = transform
    }

    public var body: Never {
        Never.bodyException()
    }

    public static func makeRequest(_ request: TupleRequest<T>, _ context: Context) async {
        await request.transformHandler(context)
    }
}
