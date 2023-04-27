/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@propertyWrapper
struct PropertyContainer<Value>: PropertyValue {

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

extension PropertyContainer {

    fileprivate class Stored {
        var value: Value

        init(_ value: Value) {
            self.value = value
        }
    }
}

extension PropertyValue {

    func container<Value>(
        _ valueType: Value.Type = Value.self
    ) -> PropertyContainer<Value>? {
        if let box = self as? PropertyContainer<Value> {
            return box
        }

        for child in Mirror(reflecting: self).children {
            if let property = child.value as? PropertyValue {
                return property.container(valueType)
            }
        }

        return nil
    }
}
