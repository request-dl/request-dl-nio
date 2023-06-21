/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A task that is intercepted by an ``RequestTaskInterceptor``.

 A ``InterceptedRequestTask`` is created by applying a ``RequestTask/interceptor(_:)`` to a base ``RequestTask``.
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
