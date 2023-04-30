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
            Headers.Cache()
                .cached(true)
        }
    }
 }
 ```

 This `DefaultHeaders` struct conforms to the Property protocol and sets default
 headers for all requests. We can use many different objects to configure requests in
 order to meet specific application requirements.
 */
@RequestActor
public protocol Property {

    associatedtype Body: Property

    /// An associated type that conforms to the `Property` protocol. This property
    /// allows you to set multiple request properties at once.
    @PropertyBuilder
    var body: Body { get }

    /// This method is used internally and should not be called directly.
    @_spi(Private)
    static func _makeProperty(
        property: _GraphValue<Self>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs
}

extension Property {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<Self>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        var inputs = inputs
        
        let operation = GraphOperation(property)
        operation(&inputs)

        return try await Body._makeProperty(
            property: property.body,
            inputs: inputs
        )
    }
}
