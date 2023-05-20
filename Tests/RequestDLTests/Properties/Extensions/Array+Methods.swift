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

    private func hasSuffix(_ suffix: [Element]) -> Bool {
        guard endIndex >= suffix.endIndex else {
            return false
        }

        let lowerBound = index(endIndex, offsetBy: -suffix.endIndex)

        return Array(self[lowerBound ..< endIndex]) == suffix
    }

    private func _components<S: Sequence>(
        separatedBy separator: S
    ) -> [[Element]] where S.Element == Element {
        var group = [[Element]]()
        var item = [Element]()
        let separator = Array(separator)

        for element in self {
            item.append(element)

            if item.hasSuffix(separator) {
                item.removeLast(separator.count)
                group.append(item)
                item = []
            }
        }

        if !item.isEmpty || hasSuffix(separator) {
            group.append(item)
            item = []
        }

        return group
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
