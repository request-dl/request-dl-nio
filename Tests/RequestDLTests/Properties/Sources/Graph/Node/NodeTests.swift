/*
 See LICENSE for this package's licensing information.
*/

import Foundation
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
        #expect(leaf.value == 1)
    }

    @Test
    func node_whenLeafNextIsCalled_shouldBeNil() async {
        // Given
        let node = Node(value: true)

        // When
        var leaf = LeafNode(node)

        let next1 = leaf.next()
        let next2 = leaf.next()

        // Then
        #expect(next1 == nil)
        #expect(next2 == nil)
    }

    @Test
    func node_whenEmptyLeafNextIsCalled_shouldBeNil() async {
        // Given
        var empty = EmptyLeafNode()

        // When
        let next1 = empty.next()
        let next2 = empty.next()

        // Then
        #expect(next1 == nil)
        #expect(next2 == nil)
    }

    @Test
    func node_whenChildrenNextIsCalledWithEmptyNodes_shouldBeNil() async {
        // Given
        var children = ChildrenNode()

        // When
        let next1 = children.next()
        let next2 = children.next()

        // Then
        #expect(next1 == nil)
        #expect(next2 == nil)
    }

    @Test
    func node_whenChildrenAppendNodesAndCallNext_shouldBeEqualNodes() async {
        // Given
        let node1 = LeafNode(Node(value: 1))
        let node2 = LeafNode(Node(value: true))

        var children = ChildrenNode()

        children.append(node1)
        children.append(node2)

        // When
        let next1 = children.next()
        let next2 = children.next()
        let next3 = children.next()

        // Then
        #expect((next1 as? LeafNode<Node<Int>>)?.value == 1)
        #expect((next2 as? LeafNode<Node<Bool>>)?.value == true)
        #expect(next3 == nil)
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
        let next1 = children1.next()
        let next2 = children1.next()
        let next3 = children1.next()
        let next4 = children1.next()

        // Then
        #expect((next1 as? LeafNode<Node<Int>>)?.value == 1)
        #expect((next2 as? LeafNode<Node<Bool>>)?.value == true)
        #expect(next3 != nil)
        #expect(next4 == nil)

        if let next3 {
            #expect(next3 is ChildrenNode)
        }
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
        let next1 = children1.next()
        let next2 = children1.next()
        let next3 = children1.next()
        let next4 = children1.next()
        let next5 = children1.next()

        // Then
        #expect((next1 as? LeafNode<Node<Int>>)?.value == 1)
        #expect((next2 as? LeafNode<Node<Bool>>)?.value == true)
        #expect((next3 as? LeafNode<Node<Int>>)?.value == 1)
        #expect((next4 as? LeafNode<Node<Bool>>)?.value == true)
        #expect(next5 == nil)
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

        children.append(children) // 2 -> 4
        children.append(children) // 4 -> 8

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
