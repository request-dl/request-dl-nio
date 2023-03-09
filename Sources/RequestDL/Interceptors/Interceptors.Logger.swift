/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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
    public struct Logger: TaskInterceptor {

        let isLogActive: Bool

        init(_ isActive: Bool) {
            isLogActive = isActive
        }

        /**
        Called when the task result is received.

        - Parameter result: The result of the task execution.
        */
        public func received(_ result: Result<TaskResult<Data>, Error>) {
            guard isLogActive else {
                return
            }

            switch result {
            case .failure(let error):
                print("[REQUEST] Failure: \(error)")
            case .success(let result):
                print("[REQUEST] Success: \(result.response)")
                print("[REQUEST] Data: \(String(data: result.data, encoding: .utf8) ?? "Couldn't decode using UTF8")")
            }
        }
    }
}

extension Task where Element == TaskResult<Data> {

    /**
     Add the `Interceptors.Logger` interceptor to log task result.

     - Parameter isActive: If `true`, the task result will be logged in the console.
     - Returns: A new instance of the `InterceptedTask` with `Interceptors.Logger` interceptor.
     */
    public func logInConsole(_ isActive: Bool) -> InterceptedTask<Interceptors.Logger, Self> {
        intercept(Interceptors.Logger(isActive))
    }
}
