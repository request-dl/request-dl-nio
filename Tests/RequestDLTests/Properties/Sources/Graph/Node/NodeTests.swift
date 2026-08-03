//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#endif
import Testing

@testable import RequestDL

struct NodeTests {

    struct Node<Value: Sendable>: PropertyNode {
        let value: Value

        func make(_ make: inout Make) async throws {}
    }

    @Test
    func node_whenLeafInitWithNode() async {
        // Given
        let value = 1

        // When
        let leaf = LeafNode(Node(value: value))

        // Then
        // O acesso a `value` funciona graças ao @dynamicMemberLookup no LeafNode
        #expect(leaf.value == 1)
    }

    @Test
    func node_whenLeafChildrenIsCalled_shouldBeEmpty() async {
        // Given
        let node = Node(value: true)

        // When
        let leaf = LeafNode(node)
        let children = leaf.children

        // Then
        #expect(children.isEmpty)
    }

    @Test
    func node_whenEmptyLeafChildrenIsCalled_shouldBeEmpty() async {
        // Given
        let empty = EmptyLeafNode()

        // When
        let children = empty.children

        // Then
        #expect(children.isEmpty)
    }

    @Test
    func node_whenChildrenChildrenIsCalledWithEmptyNodes_shouldBeEmpty() async {
        // Given
        let childrenNode = ChildrenNode()

        // When
        let children = childrenNode.children

        // Then
        #expect(children.isEmpty)
    }

    @Test
    func node_whenChildrenAppendNodesAndCheckChildren_shouldBeEqualNodes() async {
        // Given
        let node1 = LeafNode(Node(value: 1))
        let node2 = LeafNode(Node(value: true))

        var childrenNode = ChildrenNode()

        childrenNode.append(node1)
        childrenNode.append(node2)

        // When
        let children = childrenNode.children

        // Then
        #expect(children.count == 2)
        #expect((children[0] as? LeafNode<Node<Int>>)?.value == 1)
        #expect((children[1] as? LeafNode<Node<Bool>>)?.value == true)
    }

    @Test
    func node_whenChildrenAppendChildrenWithoutGrouping_shouldContainsEach() async {
        // Given
        let node1 = LeafNode(Node(value: 1))
        let node2 = LeafNode(Node(value: true))

        var children1 = ChildrenNode()
        var children2 = ChildrenNode()

        children2.append(node1)
        children2.append(node2)

        children1.append(node1)
        children1.append(node2)
        children1.append(children2)

        // When
        let children = children1.children

        // Then
        #expect(children.count == 3)
        #expect((children[0] as? LeafNode<Node<Int>>)?.value == 1)
        #expect((children[1] as? LeafNode<Node<Bool>>)?.value == true)
        #expect(children[2] is ChildrenNode)
    }

    @Test
    func node_whenChildrenAppendChildrenByGrouping_shouldContainsCombined() async {
        // Given
        let node1 = LeafNode(Node(value: 1))
        let node2 = LeafNode(Node(value: true))

        var children1 = ChildrenNode()
        var children2 = ChildrenNode()

        children2.append(node1)
        children2.append(node2)

        children1.append(node1)
        children1.append(node2)
        children1.append(children2, grouping: true)

        // When
        let children = children1.children

        // Then
        #expect(children.count == 4)
        #expect((children[0] as? LeafNode<Node<Int>>)?.value == 1)
        #expect((children[1] as? LeafNode<Node<Bool>>)?.value == true)
        #expect((children[2] as? LeafNode<Node<Int>>)?.value == 1)
        #expect((children[3] as? LeafNode<Node<Bool>>)?.value == true)
    }

    @Test
    func node_whenFirstOfContainsNode() async {
        // Given
        let node1 = LeafNode(Node(value: 1))
        let node2 = LeafNode(Node(value: 2))

        var children = ChildrenNode()

        children.append(node1)
        children.append(node2)

        // When
        let node = children.first(of: Node<Int>.self)

        // Then
        #expect(node?.value == 1)
    }

    @Test
    func node_whenFirstOfNotContainsNode() async {
        // Given
        let node1 = LeafNode(Node(value: 1))
        let node2 = LeafNode(Node(value: 2))

        var children = ChildrenNode()

        children.append(node1)
        children.append(node2)

        // When
        let node = children.first(of: Node<Bool>.self)

        // Then
        #expect(node == nil)
    }

    @Test
    func node_whenSearchAllNodes() async {
        // Given
        let node1 = LeafNode(Node(value: 1))
        let node2 = LeafNode(Node(value: 2))
        let node3 = LeafNode(Node(value: true))

        var children = ChildrenNode()

        children.append(node1)
        children.append(node2)
        children.append(node3)

        children.append(children)  // 2 -> 4
        children.append(children)  // 4 -> 8

        // When
        let nodes = children.search(for: Node<Int>.self)

        // Then
        #expect(nodes.count == 8)

        if nodes.count == 8 {
            #expect(nodes[0].value == 1)
            #expect(nodes[1].value == 2)
            #expect(nodes[2].value == 1)
            #expect(nodes[3].value == 2)
            #expect(nodes[4].value == 1)
            #expect(nodes[5].value == 2)
            #expect(nodes[6].value == 1)
            #expect(nodes[7].value == 2)
        }
    }
}
