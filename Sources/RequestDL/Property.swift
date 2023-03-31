/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `Property` protocol is the foundation of all other objects in the RequestDL library.

 The protocol provides a `body` property, which returns an opaque `some Property` type.
 By combining multiple request objects, we can use the `body` property to configure
 multiple request properties at once. This is demonstrated in the following example:

 ```swift
 struct DefaultHeaders: Property {
    let cache: Bool

    var body: some Property {
        Headers.ContentType(.json)
        Headers.Accept(.json)

        if cache {
            Cache(.returnCacheDataElseLoad)
        }
    }
 }
 ```

 This `DefaultHeaders` struct conforms to the Property protocol and sets default
 headers for all requests. We can use many different objects to configure requests in
 order to meet specific application requirements.
 */
public protocol Property {

    associatedtype Body: Property

    /// An associated type that conforms to the `Property` protocol. This property
    /// allows you to set multiple request properties at once.
    @PropertyBuilder
    var body: Body { get }

    /// This method is used internally and should not be called directly.
    static func _makeProperty(property: _GraphValue<Self>, inputs: _PropertyInputs) async throws -> _PropertyOutputs

    /// This method is used internally and should not be called directly.
    @available(*, deprecated, renamed: "_makeProperty(property:inputs:)")
    static func makeProperty(_ property: Self, _ context: Context) async throws
}

extension Property {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Self>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        try await Body._makeProperty(
            property: property.body,
            inputs: inputs[self]
        )
    }

    /// This method is used internally and should not be called directly.
    @available(*, deprecated, renamed: "_makeProperty(property:inputs:)")
    public static func makeProperty(_ property: Self, _ context: Context) async throws {
        fatalError("You shouldn't be calling this method")
    }
}
