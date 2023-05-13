/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

struct SendableBox<Value: Sendable>: Sendable {

    private let storage: Storage

    init(_ value: Value) {
        storage = .init(value)
    }

    func callAsFunction(_ value: Value) {
        storage.value = value
    }

    func callAsFunction() -> Value {
        storage.value
    }
}

extension SendableBox {

    fileprivate final class Storage: @unchecked Sendable {

        private let lock = Lock()

        private var _value: Value

        var value: Value {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }

        init(_ value: Value) {
            self._value = value
        }
    }
}
