/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A property wrapper that provides access to values stored in the `EnvironmentValues`
 object.

 The `Environment` property wrapper is used to access values that are stored in the
 `EnvironmentValues` object. This object contains values that are shared across the
 request tasks and can be accessed by any property within the request's hierarchy. By
 using the `Environment` property wrapper, you can access these values in a type-safe
 manner and with less boilerplate code.

 **Usage**

 To use the `Environment` property wrapper, create a new instance of it and pass in a
 key path that  points to the value you want to access in the `EnvironmentValues`
 object. For example, to access the `contentType` value, you can create an instance of
 `Environment` with the `\.contentType` key path:

 ```swift
 @Environment(\.contentType) var contentType: ContentType
 ```

 This will create a new property named `contentType` that you can use to access the
 `contentType` value anywhere in your property code.

 **Example**

 The following example shows how to use the `wrappedValue` property to access the
 `contentType` value in a `Property`:

 ```swift
 struct DefaultHeader: Property {

     @Environment(\.contentType) var contentType: ContentType

     var body: some Property {
         Headers.ContentType(contentType)
     }
 }
 ```
 */
@RequestActor
@propertyWrapper
public struct Environment<Value>: DynamicValue {

    @_Container private var value: Value?

    private let keyPath: KeyPath<EnvironmentValues, Value>

    /**
     Initializes a new instance of the `Environment` property wrapper.

     - Parameter keyPath: The key path that points to the value in the `EnvironmentValues` object.
     */
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    /**
     The wrapped value that provides access to the value stored in the `EnvironmentValues` object.

     To access the value stored in the `EnvironmentValues` object, use the `wrappedValue`
     property on the `Environment` property wrapper. This property returns the value that is stored
     in the `EnvironmentValues` object for the key path provided to the initializer.

     ## Example

     The following example shows how to use the `wrappedValue` property to access the
     `contentType` value in a `Property`:

     ```swift
         struct DefaultHeader: Property {

             @Environment(\.contentType) var contentType: ContentType

             var body: some Property {
                 Headers.ContentType(contentType)
             }
         }
     ```
     */
    public var wrappedValue: Value {
        guard let value else {
            Internals.Log.failure(
                .environmentNilValue(keyPath)
            )
        }

        return value
    }
}

extension Environment: DynamicEnvironment {

    func update(_ values: EnvironmentValues) {
        value = values[keyPath: keyPath]
    }
}
