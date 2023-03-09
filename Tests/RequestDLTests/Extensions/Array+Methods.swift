/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Array {

    private mutating func appendSlice<E>(_ slice: [E], at index: Index) where Element == [E], E: Equatable {
        var array = self[index]

        for element in slice {
            array.append(element)
        }

        self[index] = array
    }

    fileprivate func appendingSliceAtLast<E>(_ slice: [E]) -> [[E]] where Element == [E], E: Equatable {
        var mutableSelf = self
        mutableSelf.appendSlice(slice, at: index(endIndex, offsetBy: -1))
        return mutableSelf
    }
}

extension Array where Element: Equatable {

    private func _components<S: Sequence>(
        separatedBy separator: S
    ) -> [[Element]] where S.Element == Element {
        let separator = Array(separator)
        var combinedElements: [Element] = []

        return reduce([[]]) {
            combinedElements.append($1)

            let matches = combinedElements.count <= separator.count && combinedElements
                .enumerated()
                .allSatisfy { separator[$0] == $1 }

            if matches {
                if combinedElements == separator {
                    combinedElements = []
                    return $0 + [[]]
                } else {
                    return $0
                }
            } else {
                let pendingElements = combinedElements
                combinedElements = []
                return $0.appendingSliceAtLast(pendingElements)
            }
        }
    }

    func components<S: Sequence>(
        separatedBy separator: S,
        omittingEmptySubsequences: Bool = true
    ) -> [[Element]] where S.Element == Element {
        if omittingEmptySubsequences {
            return _components(separatedBy: separator)
                .filter { !$0.isEmpty }
        } else {
            return _components(separatedBy: separator)
        }
    }
}
