/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Namespace {

    public struct ID: Hashable {

        private let base: AnyHashable
        private let namespace: String
        private let additionalHashValue: AnyHashable

        init<Base>(
            base: Base.Type,
            namespace: String,
            hashValue: Int
        ) {
            self.base = String(describing: base)
            self.namespace = namespace
            self.additionalHashValue = hashValue
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

extension Namespace.ID: CustomStringConvertible {

    private var namespaceDescription: String {
        namespace.split(separator: ".").last.map {
            String($0)
        } ?? namespace
    }

    public var description: String {
        String(namespaceDescription.dropFirst())
    }
}
