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
     `Interceptors.LogInConsole` interceptor to log task result.

     Example:

     ```swift
     DataTask { ... }
         .logInConsole(true)
     ```

     - Note: If `isActive` is `true`, it logs task result in the console.
     */
    public struct LogInConsole<Element: Sendable>: RequestTaskInterceptor {

        // MARK: - Internal properties

        let isActive: Bool
        let results: @Sendable (Element) -> [String]

        // MARK: - Public methods

        /**
        Called when the task result is received.

        - Parameter result: The result of the task execution.
        */
        public func output(_ result: Result<Element, Error>) {
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

    @available(*, deprecated, renamed: "LogInConsole")
    public typealias Logger = LogInConsole
}

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Add the `Interceptors.LogInConsole` interceptor to log task result.

     - Parameter isActive: If `true`, the task result will be logged in the console.
     - Returns: A new instance of the `InterceptedTask` with `Interceptors.LogInConsole`
     interceptor.
     */
    public func logInConsole(
        _ isActive: Bool
    ) -> InterceptedRequestTask<Interceptors.LogInConsole<Element>> {
        interceptor(Interceptors.LogInConsole(
            isActive: isActive,
            results: {
                ["Success: \($0)"]
            }
        ))
    }
}

extension RequestTask<TaskResult<Data>> {

    /**
     Add the `Interceptors.LogInConsole` interceptor to log task result.

     - Parameter isActive: If `true`, the task result will be logged in the console.
     - Returns: A new instance of the `InterceptedTask` with `Interceptors.LogInConsole`
     interceptor.
     */
    public func logInConsole(
        _ isActive: Bool
    ) -> InterceptedRequestTask<Interceptors.LogInConsole<Element>> {
        interceptor(Interceptors.LogInConsole(
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
     Add the `Interceptors.LogInConsole` interceptor to log task result.

     - Parameter isActive: If `true`, the task result will be logged in the console.
     - Returns: A new instance of the `InterceptedTask` with `Interceptors.LogInConsole`
     interceptor.
     */
    public func logInConsole(_ isActive: Bool) -> InterceptedRequestTask<Interceptors.LogInConsole<Element>> {
        interceptor(Interceptors.LogInConsole(
            isActive: isActive,
            results: {
                ["Success: \(String(data: $0, encoding: .utf8) ?? "Couldn't decode using UTF8")"]
            }
        ))
    }
}
