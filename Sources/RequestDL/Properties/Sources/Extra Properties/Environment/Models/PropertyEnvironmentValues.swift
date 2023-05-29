/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 `PropertyEnvironmentValues` is a type that contains all of the environment values
 for a view hierarchy. It is accessible via a subscript on a view's `PropertyEnvironment`
 property.
 */
public struct PropertyEnvironmentValues: Sendable {

    // MARK: - Private properties

    private var values = [ObjectIdentifier: Sendable]()

    // MARK: - Inits

    init() {}

    // MARK: - Public methods

    /**
     Subscript for retrieving an `Value` for a given `PropertyEnvironmentKey` type.

     - Parameter key: The `PropertyEnvironmentKey` type to retrieve the `Value` for.
     - Returns: The `Value` in the environment for the given `key`.
     */
    public subscript<Key: PropertyEnvironmentKey>(key: Key.Type) -> Key.Value {
        get {
            guard let value = values[ObjectIdentifier(key)] as? Key.Value else {
                return Key.defaultValue
            }

            return value
        }
        set {
            values[ObjectIdentifier(key)] = newValue
        }
    }
}

@available(*, deprecated, renamed: "PropertyEnvironmentValues")
public typealias EnvironmentValues = PropertyEnvironmentValues
