import Foundation

struct EmptyObject<Content: Request>: NodeObject {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {}
}
