//
// See LICENSE for this package's licensing information.
//

struct DynamicValueMirror<Content: Sendable>: Sendable {

    struct Child: Sendable {
        let label: String?
        let value: DynamicValue
    }

    // MARK: - Private properties

    private let children: [Child]

    // MARK: - Inits

    init(_ content: Content) {
        // - Important: Reflected once, at construction, not lazily on every call. `GraphOperation`
        // creates three operations that each ask for the children, so a closure that rebuilt the
        // `Mirror` on every call would pay for three reflections instead of one per property in
        // the graph.
        //
        // Holding the result rather than the `Mirror` is also what makes this `Sendable`
        // without an escape hatch: `DynamicValue` is `Sendable`, `Mirror` is not.
        children = Mirror(reflecting: content).children.compactMap { child in
            (child.value as? DynamicValue).map {
                Child(label: child.label, value: $0)
            }
        }
    }

    // MARK: - Internal methods

    func callAsFunction() -> [Child] {
        children
    }
}
