/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `@PropertyNamespace` property wrapper allows you to define a namespace identifier
 for `Property` objects.

 This creates a namespace ID for storing objects inside the `Property` declaration.

 Here is an example:

 ```swift
 struct ProjectDefaults: Property {

    @PropertyNamespace var projectName
    @StateObject var pskResolver = PSKResolver()

    var property: some Property {
        SecureConnection {
            PSKIdentity(pskResolver)
        }
    }
 }
 ```

 In this example, the `pskResolver` object will be stored internally and isolated by
 the `projectName` namespace ID. If you specify multiple namespaces, they will be
 merged into a single namespace declaration.

 Here is an example where the namespace ID is `_foo._bar`:

 ```swift
 struct ProjectDefaults: Property {

    @PropertyNamespace var foo
    @PropertyNamespace var bar

    @StateObject var pskResolver = PSKResolver()

    var property: some Property {
        SecureConnection {
            PSKIdentity(pskResolver)
        }
    }
 }
 ```
 */
@propertyWrapper
public struct PropertyNamespace: DynamicValue {

    // MARK: - Public properties

    /**
     The identifier for the namespace that automatically is used to store objects inside
     the `Property` declaration in a isolated memory.
     */
    public var wrappedValue: ID {
        id ?? .global
    }

    // MARK: - Internal properties

    @_Container var id: ID?

    // MARK: - Inits

    /**
     Instantiates a namespace identifier for `Property` objects.
     */
    public init() {}
}
