/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension Interceptors {

    /**
     An interceptor for logging task result.

     Use `logInConsole(_:)` method of the `RequestTask` to add an instance of the
     `Interceptors.Logger` interceptor to log task result.

     Example:

     ```swift
     DataTask { ... }
         .logInConsole(true)
     ```

     - Note: If `isActive` is `true`, it logs task result in the console.

     - Important: `Interceptors.Logger` can be used as a reference to implement custom interceptors.
     */
    public struct Logger<Element: Sendable>: TaskInterceptor {

        // MARK: - Internal properties

        let isActive: Bool
        let results: @Sendable (Element) -> [String]

        // MARK: - Public methods

        /**
        Called when the task result is received.

        - Parameter result: The result of the task execution.
        */
        public func received(_ result: Result<Element, Error>) {
            guard isActive else {
                return
            }

            switch result {
            case .failure(let error):
                Internals.Log.debug("Failure: \(error)")
            case .success(let result):
                Internals.Log.debug(results(result).joined(separator: "\n"))
            }
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Add the `Interceptors.Logger` interceptor to log task result.

     - Parameter isActive: If `true`, the task result will be logged in the console.
     - Returns: A new instance of the `InterceptedTask` with `Interceptors.Logger` interceptor.
     */
    public func logInConsole(_ isActive: Bool) -> InterceptedTask<Interceptors.Logger<Element>, Self> {
        intercept(Interceptors.Logger(
            isActive: isActive,
            results: {
                ["Success: \($0)"]
            }
        ))
    }
}

extension RequestTask<TaskResult<Data>> {

    /**
     Add the `Interceptors.Logger` interceptor to log task result.

     - Parameter isActive: If `true`, the task result will be logged in the console.
     - Returns: A new instance of the `InterceptedTask` with `Interceptors.Logger` interceptor.
     */
    public func logInConsole(_ isActive: Bool) -> InterceptedTask<Interceptors.Logger<Element>, Self> {
        intercept(Interceptors.Logger(
            isActive: isActive,
            results: {[
                "Head: \($0.head)",
                "Payload: \(String(data: $0.payload, encoding: .utf8) ?? "Couldn't decode using UTF8")"
            ]}
        ))
    }
}

extension RequestTask<Data> {

    /**
     Add the `Interceptors.Logger` interceptor to log task result.

     - Parameter isActive: If `true`, the task result will be logged in the console.
     - Returns: A new instance of the `InterceptedTask` with `Interceptors.Logger` interceptor.
     */
    public func logInConsole(_ isActive: Bool) -> InterceptedTask<Interceptors.Logger<Element>, Self> {
        intercept(Interceptors.Logger(
            isActive: isActive,
            results: {
                ["Success: \(String(data: $0, encoding: .utf8) ?? "Couldn't decode using UTF8")"]
            }
        ))
    }
}
