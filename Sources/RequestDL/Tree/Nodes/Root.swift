/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct Root<Root: PropertyNode, Leaf: Node>: Node {

    private let root: Root
    private let leaf: Leaf
    private var index: Int = .zero

    init(_ root: Root, leaf: Leaf) {
        self.root = root
        self.leaf = leaf
    }

    mutating func next() -> Node? {
        guard index == .zero else {
            return nil
        }

        defer { index += 1 }
        return leaf
    }
}
