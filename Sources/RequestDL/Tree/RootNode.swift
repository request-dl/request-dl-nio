import Foundation

class RootNode: NodeType {

    var children: [NodeType]

    init() {
        self.children = []
    }

    func fetchObject() -> NodeObject? {
        nil
    }
}
