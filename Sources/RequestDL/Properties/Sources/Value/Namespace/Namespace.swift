/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@propertyWrapper
public struct Namespace: PropertyValue {

    @PropertyContainer var _namespaceID: ID?

    public init() {}

    public var wrappedValue: ID {
        _namespaceID ?? .global
    }
}

extension Namespace {

    public struct ID: Hashable {

        private let rawValue: String

        init<Base>(
            base: Base.Type,
            namespace: String,
            hashValue: Int
        ) {
            self.rawValue = "\(base).\(namespace):\(hashValue)"
        }
    }
}

extension Namespace.ID {

    private enum Global {}

    static var global: Self {
        .init(
            base: Global.self,
            namespace: "_global",
            hashValue: .zero
        )
    }
}
