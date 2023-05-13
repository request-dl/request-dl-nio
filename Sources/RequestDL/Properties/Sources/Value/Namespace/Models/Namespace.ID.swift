/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Namespace {

    /// The ID used for namespace memory storage.
    public struct ID: Sendable, Hashable {

        private enum Global {}

        // MARK: - Internal static properties

        static var global: Self {
            .init(
                base: Global.self,
                namespace: "_global"
            )
        }

        // MARK: - Private properties

        private let base: ObjectIdentifier
        private let namespace: String

        // MARK: - Inits

        init<Base>(
            base: Base.Type,
            namespace: String
        ) {
            self.base = .init(base)
            self.namespace = namespace
        }
    }
}

// MARK: - CustomStringConvertible

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
