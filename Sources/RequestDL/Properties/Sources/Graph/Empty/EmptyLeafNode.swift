/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct EmptyLeafNode: Node {

    init() {}

    mutating func next() -> Node? {
        nil
    }
}
