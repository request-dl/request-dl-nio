import Foundation

public struct Timeout: Request {

    public typealias Body = Never

    let timeout: TimeInterval
    let source: Source

    public init(_ timeout: TimeInterval, for source: Source = .all) {
        self.timeout = timeout
        self.source = source
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension Timeout: PrimitiveRequest {

    struct Object: NodeObject {

        let timeout: TimeInterval
        let source: Source

        init(_ timeout: TimeInterval, _ source: Source) {
            self.timeout = timeout
            self.source = source
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            if source.contains(.request) {
                configuration.timeoutIntervalForRequest = timeout
            }

            if source.contains(.resource) {
                configuration.timeoutIntervalForResource = timeout
            }
        }
    }

    func makeObject() -> Object {
        .init(timeout, source)
    }
}
