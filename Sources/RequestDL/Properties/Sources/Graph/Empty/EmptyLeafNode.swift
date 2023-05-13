/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct EmptyLeafNode: Node {

    mutating func next() -> Node? {
        nil
    }
}
