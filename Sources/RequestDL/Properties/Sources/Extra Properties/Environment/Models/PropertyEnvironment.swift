/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A property wrapper that provides access to values stored in the ``RequestEnvironmentValues``
 object.

 ## Overview

 The ``PropertyEnvironment`` property wrapper is used to access values that are stored in the
 ``RequestEnvironmentValues`` object. This object contains values that are shared across the
 request tasks and can be accessed by any property within the request's hierarchy. By
 using the ``PropertyEnvironment`` property wrapper, you can access these values in a type-safe
 manner and with less boilerplate code.

 ### Usage

 To use the ``PropertyEnvironment`` property wrapper, create a new instance of it and pass in a
 key path that  points to the value you want to access in the ``RequestEnvironmentValues``
 object. For example, to access the `contentType` value, you can create an instance of
 ``PropertyEnvironment`` with the `\.contentType` key path:

 ```swift
 @PropertyEnvironment(\.contentType) var contentType: ContentType
 ```

 This will create a new property named `contentType` that you can use to access the
 `contentType` value anywhere in your property code.

 ### Example

 The following example shows how to use the ``PropertyEnvironment/wrappedValue`` property to access the
 `contentType` value in a ``Property``.

 ```swift
 struct DefaultHeader: Property {

     @PropertyEnvironment(\.contentType) var contentType: ContentType

     var body: some Property {
         Headers.ContentType(contentType)
     }
 }
 ```
 */
@propertyWrapper
public struct PropertyEnvironment<Value: Sendable>: DynamicValue {

    // MARK: - Public properties

    /**
     The wrapped value that provides access to the value stored in the ``RequestEnvironmentValues`` object.

     To access the value stored in the ``RequestEnvironmentValues`` object, use the
     ``PropertyEnvironment/wrappedValue`` property on the ``PropertyEnvironment`` property
     wrapper. This property returns the value that is stored in the ``RequestEnvironmentValues``
     object for the key path provided to the initializer.

     ### Example

     The following example shows how to use the ``PropertyEnvironment/wrappedValue`` property to access the
     `contentType` value in a ``Property``:

     ```swift
     struct DefaultHeader: Property {

         @PropertyEnvironment(\.contentType) var contentType: ContentType

         var body: some Property {
             Headers.ContentType(contentType)
         }
     }
     ```
     */
    public var wrappedValue: Value {
        guard let value else {
            Internals.Log.environmentNilValue(keyPath)
                .preconditionFailure()
        }

        return value
    }

    // MARK: - Private properties

    @_Container private var value: Value?

    private let keyPath: @Sendable (RequestEnvironmentValues) -> Value

    // MARK: - Inits

    /**
     Initializes a new instance of the ``PropertyEnvironment`` property wrapper.

     - Parameter keyPath: The key path that points to the value in the ``RequestEnvironmentValues`` object.
     */
    public init(_ keyPath: KeyPath<RequestEnvironmentValues, Value> & Sendable) {
        self.keyPath = {
            $0[keyPath: keyPath]
        }
    }
}

// MARK: - DynamicEnvironment

extension PropertyEnvironment: DynamicEnvironment {

    func update(_ values: RequestEnvironmentValues) {
        value = keyPath(values)
    }
}
