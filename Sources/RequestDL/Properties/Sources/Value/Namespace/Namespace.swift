/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
@propertyWrapper
public struct Namespace: DynamicValue {

    @_Container var id: ID?

    public init() {}

    public var wrappedValue: ID {
        id ?? .global
    }
}
