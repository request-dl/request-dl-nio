/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A task that can be intercepted by an `Interceptor` and returns a `Content` object.

 - Interceptor: The type of `Interceptor` that will intercept the task.
 - Content: The type of `Content` that will be returned by the task.

 An `InterceptedTask` conforms to the `Task` protocol and defines a `result()` method that returns
 a `Content.Element` object. The `result()` method can throw an error asynchronously.
 */
public struct InterceptedTask<
    Interceptor: TaskInterceptor, Content: Task
>: Task where Interceptor.Element == Content.Element {

    public typealias Element = Content.Element

    let task: Content
    let interceptor: Interceptor

    init(_ task: Content, _ interceptor: Interceptor) {
        self.task = task
        self.interceptor = interceptor
    }
}

extension InterceptedTask {

    /**
     Returns the result of the task.

     - Throws: An error of type `Error` if the task could not be completed.

     - Returns: An object of type `Element` with the result of the task.
     */
    public func result() async throws -> Element {
        do {
            let result = try await task.result()
            interceptor.received(.success(result))
            return result
        } catch {
            interceptor.received(.failure(error))
            throw error
        }
    }
}