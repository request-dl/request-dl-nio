/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import _RequestDLExtensions

extension Interceptors {

    /**
     An interceptor for logging task result.

     Use `logInConsole(_:)` method of the `Task` to add an instance of the
     `Interceptors.Logger` interceptor to log task result.

     Example:

     ```swift
     DataTask { ... }
         .logInConsole(true)
     ```

     - Note: If `isActive` is `true`, it logs task result in the console.

     - Important: `Interceptors.Logger` can be used as a reference to implement custom interceptors.
     */
    public struct Logger<Element>: TaskInterceptor {

        let isLogActive: Bool
        let results: (Element) -> [String]

        init(
            isActive: Bool,
            results: @escaping (Element) -> [String]
        ) {
            isLogActive = isActive
            self.results = results
        }

        /**
        Called when the task result is received.

        - Parameter result: The result of the task execution.
        */
        public func received(_ result: Result<Element, Error>) {
            guard isLogActive else {
                return
            }

            switch result {
            case .failure(let error):
                print("[RequestDL] Failure: \(error)")
            case .success(let result):
                for line in results(result) {
                    print("[RequestDL]", line)
                }
            }
        }
    }
}

extension Task {

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

extension Task<TaskResult<Data>> {

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

extension Task<Data> {

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
