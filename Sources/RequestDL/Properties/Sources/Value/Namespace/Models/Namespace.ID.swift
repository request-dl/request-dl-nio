/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Namespace {

    /// The ID used for namespace memory storage.
    public struct ID: Hashable {

        private let base: ObjectIdentifier
        private let namespace: String

        init<Base>(
            base: Base.Type,
            namespace: String
        ) {
            self.base = .init(base)
            self.namespace = namespace
        }
    }
}

extension Namespace.ID {

    private enum Global {}

    static var global: Self {
        .init(
            base: Global.self,
            namespace: "_global"
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
