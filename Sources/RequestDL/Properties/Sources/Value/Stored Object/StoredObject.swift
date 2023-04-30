/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A property wrapper that defines a stored object inside `Property` objects.

 This wrapper can be used to store any type of object inside the property declaration.
 The object will be stored in memory.

 Example:

 ```swift
 struct MyProperty: Property {
    @StoredObject var myObject = MyClass()

    var body: some Property {
        ...
    }
 }
 ```

 In this example, an instance of `MyClass` will be stored in the `myObject` property, using
 the `StoredObject` wrapper. The object will be stored in memory until the conditions of
 expiring the reference is meet. See `Internal.Storage` for details.

 - Note: The object type must be a class that conforms to `AnyObject` protocol.
 */
@propertyWrapper
public struct StoredObject<Object: AnyObject>: DynamicValue {

    @_Container private var configuration: StoredObjectConfiguration?
    private let thunk: () -> Object

    /**
     Initializes a new `StoredObject` with the given object.

     - Parameter wrappedValue: The object that will be stored in memory.
     */
    public init(wrappedValue thunk: @autoclosure @escaping () -> Object) {
        self.thunk = thunk
    }

    /// The stored object in memory.
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
