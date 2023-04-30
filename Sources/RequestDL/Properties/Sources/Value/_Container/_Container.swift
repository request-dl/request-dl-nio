/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
@propertyWrapper
struct _Container<Value>: DynamicValue {

    private let stored: Stored

    init(wrappedValue: Value) {
        self.stored = .init(wrappedValue)
    }

    init() where Value: ExpressibleByNilLiteral {
        self.stored = .init(.init(nilLiteral: ()))
    }

    var wrappedValue: Value {
        get { stored.value }
        nonmutating
        set { stored.value = newValue }
    }
}

extension _Container {

    fileprivate class Stored {
        var value: Value

        init(_ value: Value) {
            self.value = value
        }
    }
}
