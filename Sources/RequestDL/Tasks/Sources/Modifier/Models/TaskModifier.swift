/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A protocol for modifying tasks and returning an element of a specific type.

 The `TaskModifier` protocol has two associated types: `Body` and `Element`. `Body`
 is the type of the task being modified, and `Element` is the type of the returned value after the modification.

 The `task` function takes in a `Body` task and returns an `Element` value after applying
 the modification logic.
 */
public protocol TaskModifier<Element> {

    /// The type of task being modified.
    associatedtype Body: Task

    /// The type of the returned element after modification.
    associatedtype Element

    /**
     Modifies the given task and returns an element of a specific type.

     - Parameter task: The task being modified.

     - Throws: An error of type `Error` if an error occurs during modification.

     - Returns: The modified element of type `Element`.
     */
    func task(_ task: Body) async throws -> Element
}
