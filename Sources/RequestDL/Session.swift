import Foundation

public struct Session: Request {

    public typealias Body = Never

    private let configuration: Configuration
    private let queue: OperationQueue?

    public init(_ configuration: Configuration) {
        self.configuration = configuration
        self.queue = nil
    }

    public init(_ configuration: Configuration, queue: OperationQueue) {
        self.configuration = configuration
        self.queue = queue
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension Session {

    public enum Configuration {

        case `default`
        case ephemeral

        /// [BETA]: Report in case of errors
        case background(String)

        var sessionConfiguration: URLSessionConfiguration {
            switch self {
            case .default:
                return .default
            case .ephemeral:
                return .ephemeral
            case .background(let identifier):
                return .background(withIdentifier: identifier)
            }
        }
    }
}

extension Session: PrimitiveRequest {

    struct Object: NodeObject {

        let configuration: Configuration
        let queue: OperationQueue?

        init(_ configuration: Configuration, _ queue: OperationQueue?) {
            self.configuration = configuration
            self.queue = queue
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {}
    }

    func makeObject() -> Object {
        .init(configuration, queue)
    }
}
