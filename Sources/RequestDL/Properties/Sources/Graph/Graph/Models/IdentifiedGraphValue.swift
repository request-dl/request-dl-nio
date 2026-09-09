//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

protocol IdentifiedGraphValue: Sendable {

    var id: GraphID { get }
    var nextID: GraphID? { get }

    /// Identity of the position this value occupies in the graph.
    ///
    /// - Important: Must be stored, not derived by walking the whole ancestor chain and hashing
    /// the resulting array on every read — `GraphOperation` reads this once per property, so
    /// that walk would make resolving a graph cost O(properties x depth). Folding each id into
    /// the parent's value at construction makes it O(1) per node and gives the same guarantee,
    /// since it is only ever compared against other pathways inside the same process.
    var pathway: Int { get }

    var previousValue: IdentifiedGraphValue? { get }
}

extension IdentifiedGraphValue {

    static func pathway(id: GraphID, previousValue: IdentifiedGraphValue?) -> Int {
        var hasher = Hasher()
        hasher.combine(previousValue?.pathway ?? .zero)
        hasher.combine(id)
        return hasher.finalize()
    }

    func assertPathway() {
        guard let previousValue else {
            return
        }

        if previousValue.nextID == id {
            return
        }

        // Was a `preconditionFailure`. This guards structural coherence of the graph, not
        // memory safety, so it belongs in development rather than in a user's app.
        Internals.Log.unexpectedGraphPathway()
            .assertionFailure(logger: PropertyResolutionLogger.current)
    }
}
