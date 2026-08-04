//
// See LICENSE for this package's licensing information.
//

extension PropertyNamespace {

    /// The ID used for namespace memory storage.
    public struct ID: Sendable, Hashable {

        private enum Global {}

        // MARK: - Internal static properties

        // `let`, not a computed `var`. `PropertyNamespace.wrappedValue` falls back to this on
        // every read, and recomputing rebuilt the value and looked up type metadata each time.
        static let global = Self(
            base: Global.self,
            namespace: "_global"
        )

        // MARK: - Private properties

        private let base: ObjectIdentifier
        private let namespace: String

        // Carried for ``description`` only. Two namespaces can share a label and still be
        // different ids, and telling them apart is the whole reason this type exists, so a
        // description that cannot show which property they belong to is not describing much.
        private let baseName: String

        // MARK: - Inits

        init<Base>(
            base: Base.Type,
            namespace: String
        ) {
            self.base = .init(base)
            self.namespace = namespace
            self.baseName = String(describing: base)
        }
    }
}

// MARK: - Hashable

extension PropertyNamespace.ID {

    // Written out rather than synthesised, to keep `baseName` out of identity.
    //
    // Sound because the excluded field is a pure function of an included one: equal `base`
    // always means equal `baseName`, so omitting it changes no outcome. Note this is the
    // opposite of hashing more than you compare, which does break the `Hashable` contract.
    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.base == rhs.base && lhs.namespace == rhs.namespace
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(base)
        hasher.combine(namespace)
    }
}

// MARK: - CustomStringConvertible

extension PropertyNamespace.ID: CustomStringConvertible {

    public var description: String {
        guard self != .global else {
            return "global"
        }

        return "\(baseName).\(namespacePath)"
    }

    /// Every component, not just the last one, with the property wrapper's leading underscore
    /// removed where there is one.
    ///
    /// - Important: Must not take `split(separator: ".").last` and then `dropFirst()` — that
    /// would report `bar` for `_foo._bar`, losing the rest of the path, and would turn a missing
    /// label's `nil` into `il`.
    private var namespacePath: String {
        namespace
            .split(separator: ".")
            .map { $0.hasPrefix("_") ? $0.dropFirst() : $0 }
            .joined(separator: ".")
    }
}
