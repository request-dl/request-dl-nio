//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// A platform-agnostic snapshot of a network path's availability characteristics.
    ///
    /// Exists because `Network.framework`'s own `NWPath` has no public initializer, so nothing
    /// built directly on it could be exercised by a fake in a unit test --
    /// ``Internals/NetworkPathGate`` and ``Internals/NetworkPathObserving`` are written against
    /// this type instead, never against `NWPath` directly.
    package struct NetworkPath: Sendable, Equatable {

        // MARK: - Internal properties

        package var isSatisfied: Bool
        package var usesCellular: Bool
        package var isExpensive: Bool
        package var isConstrained: Bool

        // MARK: - Inits

        package init(
            isSatisfied: Bool,
            usesCellular: Bool,
            isExpensive: Bool,
            isConstrained: Bool
        ) {
            self.isSatisfied = isSatisfied
            self.usesCellular = usesCellular
            self.isExpensive = isExpensive
            self.isConstrained = isConstrained
        }
    }
}
