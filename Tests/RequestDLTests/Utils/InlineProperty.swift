import Foundation
@testable import RequestDL

struct InlineProperty<Value>: Sendable {

    private class Storage: @unchecked Sendable {

        var wrappedValue: Value {
            get { lock.withLock { _wrappedValue } }
            set { lock.withLock { _wrappedValue = newValue } }
        }

        private let lock = Lock()

        private var _wrappedValue: Value

        init(wrappedValue: consuming Value) {
            self._wrappedValue = wrappedValue
        }
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating
        set { storage.wrappedValue = newValue }
    }

    private let storage: Storage

    init(wrappedValue: Value) {
        storage = .init(wrappedValue: wrappedValue)
    }
}
