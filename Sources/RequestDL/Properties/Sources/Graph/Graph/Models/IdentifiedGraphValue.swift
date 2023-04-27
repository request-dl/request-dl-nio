/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol IdentifiedGraphValue {

    var id: AnyHashable { get }
    var nextID: AnyHashable? { get }

    var previousValue: IdentifiedGraphValue? { get }
}

extension IdentifiedGraphValue {

    var pathwayHashValue: Int {
        guard let previousValue else {
            return id.hashValue
        }

        let graph = sequence(first: previousValue, next: { $0.previousValue })
        var hashes = [AnyHashable]()

        for value in graph {
            if let nextID = value.nextID {
                hashes.append(nextID)
            } else if value.previousValue == nil {
                hashes.append(value.id)
            } else {
                break
            }
        }

        return hashes.hashValue
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
