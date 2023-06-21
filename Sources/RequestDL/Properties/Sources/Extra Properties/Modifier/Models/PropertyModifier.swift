/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The ``PropertyModifier`` protocol defines a type that can modify a ``Property`` type.

 This protocol requires the definition of an associated type `Body` that must be a ``Property``
 type, as well as a function ``PropertyModifier/body(content:)`` that takes in a `Content` parameter and returns a `Body`.
 */
public protocol PropertyModifier: Sendable {

    typealias Content = _PropertyModifier_Content<Self>

    associatedtype Body: Property

    /**
     Returns a modified ``Property`` type based on the given `Content`.

     - Parameter content: The `Content` used to modify the ``Property``.
     - Returns: A modified ``Property`` type.
     */
    @PropertyBuilder func body(content: Self.Content) -> Self.Body
}
