import Foundation

public protocol TaskResultPrimitive {

    var response: URLResponse { get }
}

public struct TaskResult<Element>: TaskResultPrimitive {
    public let response: URLResponse
    public let data: Element

    public init(response: URLResponse, data: Element) {
        self.response = response
        self.data = data
    }
}
