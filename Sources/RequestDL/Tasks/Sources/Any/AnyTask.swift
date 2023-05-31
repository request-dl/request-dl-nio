/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type-erasing task that wraps another task that has an associated type of Element.
 The AnyTask type forwards its operations to an underlying task object, hiding its
 specific underlying type.

 Example:

 ```swift
 func makeRequest() -> AnyTask<TaskResult<Data>> {
     DataTask {
         BaseURL("google.com")
     }
     .eraseToAnyTask()
 }
 ```
 */
public struct AnyTask<Element: Sendable>: RequestTask {

    // MARK: - Private properties

    private let wrapper: @Sendable () async throws -> Element

    // MARK: - Inits

    init<T: RequestTask>(_ task: T) where T.Element == Element {
        wrapper = { try await task.result() }
    }

    // MARK: - Public methods

    /**
     Returns the result of the wrapped task.

     - Returns: The result of the wrapped task.

     - Throws: If the wrapped task throws an error.
     */
    public func result() async throws -> Element {
        try await wrapper()
    }
}

// MARK: - Task extension

extension RequestTask {

    /**
     Returns an `AnyTask` instance that wraps `self`.

     - Returns: An `AnyTask` instance that wraps `self`.
     */
    public func eraseToAnyTask() -> AnyTask<Element> {
        .init(self)
    }
}
