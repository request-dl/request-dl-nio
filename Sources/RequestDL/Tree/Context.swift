import Foundation

public class Context {

    let root: NodeType

    init(_ root: NodeType) {
        self.root = root
    }

    @discardableResult
    func append(_ node: NodeType) -> Context {
        root.children.append(node)
        return .init(node)
    }
}

extension Context {

    private static func debug(in level: Int, node: NodeType) {
        let offset = (0..<level).map { _ in "\t" }.joined(separator: "")
        print([offset, "\(node)"].filter { !$0.isEmpty }.joined(separator: " "))

        node.children.forEach {
            debug(in: level + 1, node: $0)
        }
    }

    func debug() {
        Self.debug(in: .zero, node: root)
    }
}

extension Context {

    private static func find<Object: NodeObject>(_ objectType: Object.Type, in node: NodeType) -> Object? {
        if let node = node as? Node<Object> {
            return node.object()
        }

        for node in node.children {
            if let node = find(objectType, in: node) {
                return node
            }
        }

        return nil
    }

    func find<Object: NodeObject>(_ objectType: Object.Type) -> Object? {
        Self.find(objectType, in: root)
    }
}

extension Context {

    private static func findCollection<Object: NodeObject>(_ objectType: Object.Type, in node: NodeType) -> [Object] {
        var nodes = [Object]()

        if let node = node as? Node<Object> {
            nodes.append(node.object())
        }

        node.children.forEach {
            nodes.append(contentsOf: findCollection(objectType, in: $0))
        }

        return nodes
    }

    func findCollection<Object: NodeObject>(_ objectType: Object.Type) -> [Object] {
        Self.findCollection(objectType, in: root)
    }
}

extension Context {

    private static func make(
        _ request: inout URLRequest,
        configuration: inout URLSessionConfiguration,
        delegate: DelegateProxy,
        in node: NodeType
    ) {
        node.fetchObject()?.makeRequest(&request, configuration: &configuration, delegate: delegate)

        for node in node.children {
            make(&request, configuration: &configuration, delegate: delegate, in: node)
        }
    }

    func make(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
        Self.make(&request, configuration: &configuration, delegate: delegate, in: root)
    }
}
