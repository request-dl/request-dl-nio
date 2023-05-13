/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

struct SendableBox<Value: Sendable>: Sendable {

    // MARK: - Private properties

    private let storage: Storage

    // MARK: - Inits

    init(_ value: Value) {
        storage = .init(value)
    }

    // MARK: - Internal methods

    func callAsFunction(_ value: Value) {
        storage.value = value
    }

    func callAsFunction() -> Value {
        storage.value
    }
}

extension SendableBox {

    fileprivate final class Storage: @unchecked Sendable {

        // MARK: - Internals properties

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
