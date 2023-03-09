/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
A struct representing an empty task result. Conforms to the  `TaskError` and the `LocalizedError`
protocol.

This struct can be used to represent a task result that is empty.
*/
public struct EmptyResultError: TaskError, LocalizedError {

    public var errorDescription: String? {
        return "The result was empty."
    }
}
