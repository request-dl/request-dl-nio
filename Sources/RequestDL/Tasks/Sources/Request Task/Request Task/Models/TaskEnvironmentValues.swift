/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// ``TaskEnvironmentValues`` is a type that contains all of the environment values for a task.
public struct TaskEnvironmentValues: @unchecked Sendable {

    @TaskLocal
    static var current = TaskEnvironmentValues()

    // MARK: - Unsafe properties

    private var dependencies = [ObjectIdentifier: Sendable]()

    // MARK: - Inits

    init() {}

    // MARK: - Public methods

    /**
     Subscript for retrieving an `Value` for a given ``TaskEnvironmentKey`` type.

     - Parameter key: The ``TaskEnvironmentKey`` type to retrieve the `Value` for.
     - Returns: The `Value` in the environment for the given `Key`.
     */
    public subscript<Key: TaskEnvironmentKey>(_ keyType: Key.Type) -> Key.Value {
        get {
            let value = dependencies[ObjectIdentifier(keyType)] as? Key.Value
            return value ?? Key.defaultValue
        }
        set {
            dependencies[ObjectIdentifier(keyType)] = newValue
        }
    }
}

extension TaskEnvironmentValues {

    func callAsFunction() -> PropertyEnvironmentValues {
        var environment = PropertyEnvironmentValues()
        environment.logger = logger
        return environment
    }
}
