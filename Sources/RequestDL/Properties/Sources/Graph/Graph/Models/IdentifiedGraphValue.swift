/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol IdentifiedGraphValue: Sendable {

    var id: GraphID { get }
    var nextID: GraphID? { get }

    var previousValue: IdentifiedGraphValue? { get }
}

extension IdentifiedGraphValue {

    var pathway: Int {
        sequence(
            first: self as IdentifiedGraphValue,
            next: { $0.previousValue }
        )
        .map(\.id)
        .hashValue
    }

    func assertPathway() {
        guard let previousValue else {
            return
        }

        if previousValue.nextID == id {
            return
        }

        Internals.Log.failure(
            .unexpectedGraphPathway()
        )
    }
}
