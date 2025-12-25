/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

import Logging

extension Interceptors {

    /**
     An interceptor for logging task result.

     Use `logInConsole(_:)` method of the `RequestTask` to add an instance of the
     `Interceptors.LogInConsole` interceptor to log task result.

     ```swift
     DataTask { ... }
         .logInConsole(true)
     ```

     > Note: If `isActive` is `true`, it logs task result in the console.
     */
    public struct LogInConsole<Element: Sendable>: RequestTaskInterceptor {

        // MARK: - Internal properties

        let isActive: Bool
        let results: @Sendable (Element) -> [String]

        @TaskEnvironment(\.logger) private var logger

        // MARK: - Public methods

        /**
        Called when the task result is received.

        - Parameter result: The result of the task execution.
        */
        public func output(_ result: Result<Element, Error>) {
            guard isActive else {
                return
            }

            #if DEBUG
            let message: String

            switch result {
            case .failure(let error):
                message = "Failure: \(error)"
            case .success(let result):
                message = results(result).joined(separator: "\n")
            }

            if let logger = logger {
                logger.debug(.init(stringLiteral: message))
            } else {
                print(message)
            }
            #endif
        }
    }
}

// MARK: - RequestTask extension

@available(*, deprecated, message: "Manual console logging is no longer needed—`RequestTask` logs results automatically.")
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
                switch $0 {
                case let result as TaskResult<Data>:
                    return result.logInConsoleOutput()
                case let data as Data:
                    return [data.safeLogDescription()]
                default:
                    return ["\($0)"]
                }
            }
        ))
    }
}

@available(*, deprecated, message: "Manual console logging is no longer needed—`RequestTask` logs results automatically.")
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
            results: {
                $0.logInConsoleOutput()
            }
        ))
    }
}

@available(*, deprecated, message: "Manual console logging is no longer needed—`RequestTask` logs results automatically.")
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
                [$0.safeLogDescription()]
            }
        ))
    }
}

extension TaskResult {

    fileprivate func logInConsoleOutput() -> [String] {
        var contents = [
            "Head: \(head)"
        ]

        if let payload = payload as? Data {
            contents.append("\n" + payload.safeLogDescription())
        } else {
            contents.append("\n" + String(describing: payload))
        }

        return contents
    }
}
