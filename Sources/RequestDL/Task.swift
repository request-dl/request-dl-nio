import Foundation

/**
 The Task defines the objects that make the request.

 For the URLRequest, each request is considered as a URLSessionDownloadTask
 that allows the monitoring and cancellation of the request through it. In the case of
 the protocol, the concept of Task is used to assemble the request and execute it when
 the onResponse function is called.
 */
public protocol Task {

    associatedtype Element

    func response() async throws -> Element
}

extension Task {

    public func intercept<Middleware: MiddlewareType>(
        _ middleware: Middleware
    ) -> InterceptedTask<Middleware, Self> {
        InterceptedTask(self, middleware)
    }

    public func modify<Modifier: TaskModifier>(
        _ modifier: Modifier
    ) -> ModifiedTask<Modifier> where Modifier.Body == Self {
        ModifiedTask(self, modifier)
    }
}
