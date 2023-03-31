/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct EnvironmentValues {

    private var values = [AnyHashable: Any]()

    init() {}

    subscript<Key: EnvironmentKey>(key: Key.Type) -> Key.Value {
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
