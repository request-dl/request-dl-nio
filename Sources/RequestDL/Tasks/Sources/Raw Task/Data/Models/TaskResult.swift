/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A protocol that defines the properties and methods required for a primitive task result.
 */
public protocol TaskResultPrimitive: Sendable {

    var head: ResponseHead { get }
}

/**
 A structure that represents the result of a task.
*/
public struct TaskResult<Element: Sendable>: TaskResultPrimitive {

    // MARK: - Public properties

    /// The response head of the task result.
    public let head: ResponseHead

    /// The payload of the task result.
    public let payload: Element

    // MARK: - Inits

    /**
     Initializes a new instance of the TaskResult struct.

     - Parameters:
        - head: The response head of the task result.
        - payload: The payload of the task result.
     */
    public init(
        head: ResponseHead,
        payload: Element
    ) {
        self.head = head
        self.payload = payload
    }
}
