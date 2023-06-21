/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The ``RequestTaskModifier`` protocol defines a type that can modify a ``RequestTask`` type.

 This protocol requires the definition of an associated type `Input` and `Output` that must be a ``Sendable``
 type. The  ``RequestTaskModifier/body(_:)`` takes in a `Content` task and returns the modified `Output`.
 */
public protocol RequestTaskModifier<Input, Output>: Sendable {

    typealias Content = _RequestTaskModifier_Content<Self>

    associatedtype Input: Sendable

    associatedtype Output: Sendable

    /**
     Returns a modified `Output` based on the given `Content`.

     - Parameter task: The `Content` used to modify the ``RequestTask``.
     - Returns: A modified `Output` object.
     */
    func body(_ task: Self.Content) async throws -> Output
}
