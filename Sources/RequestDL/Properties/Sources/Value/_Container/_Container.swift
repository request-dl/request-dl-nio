/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@propertyWrapper
struct _Container<Value>: DynamicValue {

    // MARK: - Internal properties

    var wrappedValue: Value {
        get { storage.value }
        nonmutating
        set { storage.value = newValue }
    }

    // MARK: - Private properties

    private let storage: Storage

    // MARK: - Inits

    init(wrappedValue: Value) {
        self.storage = .init(wrappedValue)
    }

    init() where Value: ExpressibleByNilLiteral {
        self.storage = .init(.init(nilLiteral: ()))
    }
}

extension _Container {

    fileprivate final class Storage: @unchecked Sendable {

        // MARK: - Internal properties

        var value: Value {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _value: Value

        // MARK: - Inits

        init(_ value: Value) {
            self._value = value
        }
    }
}
