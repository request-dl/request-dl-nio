/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type-erasing task that wraps another task.

 The ``AnyTask`` type forwards its operations to an underlying task object, hiding its specific underlying type.

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

    private let task: any RequestTask<Element>

    // MARK: - Inits

    init<T: RequestTask>(_ task: T) where T.Element == Element {
        self.task = task
    }

    // MARK: - Public methods

    /**
     Returns the result of the wrapped task.

     - Returns: The result of the wrapped task.

     - Throws: If the wrapped task throws an error.
     */
    public func result() async throws -> Element {
        try await task.result()
    }
}

// MARK: - Task extension

extension RequestTask {

    /**
     Returns an ``AnyTask`` instance that wraps the current ``RequestTask``.

     - Returns: An ``AnyTask`` instance.
     */
    public func eraseToAnyTask() -> AnyTask<Element> {
        .init(self)
    }
}
