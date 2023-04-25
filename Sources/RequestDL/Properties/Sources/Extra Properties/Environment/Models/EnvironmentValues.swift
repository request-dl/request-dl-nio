/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 `EnvironmentValues` is a type that contains all of the environment values
 for a view hierarchy. It is accessible via a subscript on a view's `Environment`
 property.
 */
public struct EnvironmentValues {

    private var values = [AnyHashable: Any]()

    init() {}

    /**
     Subscript for retrieving an `Value` for a given `EnvironmentKey` type.

     - Parameter key: The `EnvironmentKey` type to retrieve the `Value` for.
     - Returns: The `Value` in the environment for the given `key`.
     */
    public subscript<Key: EnvironmentKey>(key: Key.Type) -> Key.Value {
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
