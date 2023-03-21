/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Array<UInt8> {

    func split(by size: Int) -> [Data] {
        reduce([Data]()) {
            guard var last = $0.last else {
                return [Data([$1])]
            }

            if last.count == size {
                return $0 + [Data([$1])]
            } else {
                last.append($1)
                return $0.dropLast() + [last]
            }
        }
    }
}
