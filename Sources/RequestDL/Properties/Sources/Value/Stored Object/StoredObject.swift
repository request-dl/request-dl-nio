/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@propertyWrapper
public struct StoredObject<Object: AnyObject>: DynamicValue {

    @_Container private var configuration: StoredObjectConfiguration?
    private let thunk: () -> Object

    public init(wrappedValue thunk: @autoclosure @escaping () -> Object) {
        self.thunk = thunk
    }

    public var wrappedValue: Object {
        let key = Key(configuration: configuration ?? .global)

        if let value = Internals.Storage.shared.getValue(Object.self, forKey: key) {
            return value
        }

        let value = thunk()
        Internals.Storage.shared.setValue(value, forKey: key)
        return value
    }
}

extension StoredObject {

    fileprivate struct Key: Hashable {

        let configuration: StoredObjectConfiguration

        func hash(into hasher: inout Hasher) {
            hasher.combine(configuration)
            hasher.combine(ObjectIdentifier(Object.self))
        }
    }
}

extension StoredObject: DynamicStoredObject {

    func update(_ configuration: StoredObjectConfiguration) {
        self.configuration = configuration
    }
}
