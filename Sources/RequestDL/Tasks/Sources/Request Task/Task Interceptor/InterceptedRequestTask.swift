/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A task that can be intercepted by an `Interceptor` and returns a `Content` object.

 - Interceptor: The type of `Interceptor` that will intercept the task.
 - Content: The type of `Content` that will be returned by the task.

 An `InterceptedTask` conforms to the `RequestTask` protocol and defines a `result()`
 method that returns a `Content.Element` object. The `result()` method can throw an error
 asynchronously.
 */
public struct InterceptedRequestTask<Interceptor: RequestTaskInterceptor>: RequestTask {

    public typealias Element = Interceptor.Element

    // MARK: - Public properties

    @_spi(Private)
    public var environment: TaskEnvironmentValues {
        get { task.environment }
        set { task.environment = newValue }
    }

    // MARK: - Internal properties

    var task: any RequestTask<Element>
    let interceptor: Interceptor

    // MARK: - Public methods

    /**
     Returns the result of the task.

     - Throws: An error of type `Error` if the task could not be completed.

     - Returns: An object of type `Element` with the result of the task.
     */
    public func result() async throws -> Element {
        do {
            let result = try await task.result()
            interceptor.output(.success(result))
            return result
        } catch {
            interceptor.output(.failure(error))
            throw error
        }
    }
}
