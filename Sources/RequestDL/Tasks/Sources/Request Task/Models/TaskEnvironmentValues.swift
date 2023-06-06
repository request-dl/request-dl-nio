/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct TaskEnvironmentValues: @unchecked Sendable {

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _dependencies = [ObjectIdentifier: Sendable]()

    // MARK: - Inits

    init() {}

    // MARK: - Public methods

    public subscript<Key: TaskEnvironmentKey>(_ keyType: Key.Type) -> Key.Value {
        get {
            lock.withLock {
                let value = _dependencies[ObjectIdentifier(keyType)] as? Key.Value
                return value ?? Key.defaultValue
            }
        }
        set {
            lock.withLock {
                _dependencies[ObjectIdentifier(keyType)] = newValue
            }
        }
    }
}
