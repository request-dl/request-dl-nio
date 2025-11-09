/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 This protocol defines a dynamic value used within `Property` objects.

 It is possible to implement a custom `DynamicValue` using the `@propertyWrapper`
 attribute along with a `@StoredObject` attribute inside it.

 ```swift
 @propertyWrapper
 struct MyWrapper: DynamicValue {

     @StoredObject var manager = MyManager()

     var wrappedValue: MyManager {
         manager
     }
 }
 ```

 In the above example, the `MyWrapper` structure conforms to `DynamicValue` and contains
 a `@StoredObject` variable named `manager`. This allows `MyWrapper` to be used as a
 property wrapper with a `MyManager` instance as its wrapped value.

 ```swift
 struct MyProperty: Property {

    @MyWrapper var manager

    var body: some Property {
        HeaderGroup(manager.headers)
    }
 }
 ```
*/
public protocol DynamicValue: Sendable {}
