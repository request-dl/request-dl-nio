  /*
 See LICENSE for this package's licensing information.
*/

import Foundation

class Node<Object: NodeObject>: NodeType {

    weak var root: NodeType?
    let object: () -> Object
    var children: [NodeType]

    init(object: @autoclosure @escaping () -> Object, children: [NodeType]) {
        self.root = nil
        self.object = object
        self.children = children
    }

    init(root: NodeType, object: @autoclosure @escaping () -> Object, children: [NodeType]) {
        self.root = root
        self.object = object
        self.children = children
    }

    func fetchObject() -> NodeObject? {
        object()
    }
}
