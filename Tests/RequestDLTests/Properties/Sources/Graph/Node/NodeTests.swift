/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class NodeTests: XCTestCase {

    struct Node<Value: Sendable>: PropertyNode {
        let value: Value

        func make(_ make: inout Make) async throws {}
    }

    func testNode_whenLeafInitWithNode() async {
        // Given
        let value = 1

        // When
        let leaf = LeafNode(Node(value: value))

        // Then
        XCTAssertEqual(leaf.value, 1)
    }

    func testNode_whenLeafNextIsCalled_shouldBeNil() async {
        // Given
        let node = Node(value: true)

        // When
        var leaf = LeafNode(node)

        let next1 = leaf.next()
        let next2 = leaf.next()

        // Then
        XCTAssertNil(next1)
        XCTAssertNil(next2)
    }

    func testNode_whenEmptyLeafNextIsCalled_shouldBeNil() async {
        // Given
        var empty = EmptyLeafNode()

        // When
        let next1 = empty.next()
        let next2 = empty.next()

        // Then
        XCTAssertNil(next1)
        XCTAssertNil(next2)
    }

    func testNode_whenChildrenNextIsCalledWithEmptyNodes_shouldBeNil() async {
        // Given
        var children = ChildrenNode()

        // When
        let next1 = children.next()
        let next2 = children.next()

        // Then
        XCTAssertNil(next1)
        XCTAssertNil(next2)
    }

    func testNode_whenChildrenAppendNodesAndCallNext_shouldBeEqualNodes() async {
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
        XCTAssertEqual((next1 as? LeafNode<Node<Int>>)?.value, 1)
        XCTAssertEqual((next2 as? LeafNode<Node<Bool>>)?.value, true)
        XCTAssertNil(next3)
    }

    func testNode_whenChildrenAppendChildrenWithoutGrouping_shouldContainsEach() async {
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
        XCTAssertEqual((next1 as? LeafNode<Node<Int>>)?.value, 1)
        XCTAssertEqual((next2 as? LeafNode<Node<Bool>>)?.value, true)
        XCTAssertNotNil(next3)
        XCTAssertNil(next4)

        if let next3 {
            XCTAssertTrue(next3 is ChildrenNode)
        }
    }

    func testNode_whenChildrenAppendChildrenByGrouping_shouldContainsCombined() async {
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
        XCTAssertEqual((next1 as? LeafNode<Node<Int>>)?.value, 1)
        XCTAssertEqual((next2 as? LeafNode<Node<Bool>>)?.value, true)
        XCTAssertEqual((next3 as? LeafNode<Node<Int>>)?.value, 1)
        XCTAssertEqual((next4 as? LeafNode<Node<Bool>>)?.value, true)
        XCTAssertNil(next5)
    }

    func testNode_whenFirstOfContainsNode() async {
        // Given
        let node1 = LeafNode(Node(value: 1))
        let node2 = LeafNode(Node(value: 2))

        var children = ChildrenNode()

        children.append(node1)
        children.append(node2)

        // When
        let node = children.first(of: Node<Int>.self)

        // Then
        XCTAssertEqual(node?.value, 1)
    }

    func testNode_whenFirstOfNotContainsNode() async {
        // Given
        let node1 = LeafNode(Node(value: 1))
        let node2 = LeafNode(Node(value: 2))

        var children = ChildrenNode()

        children.append(node1)
        children.append(node2)

        // When
        let node = children.first(of: Node<Bool>.self)

        // Then
        XCTAssertNil(node)
    }

    func testNode_whenSearchAllNodes() async {
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
        XCTAssertEqual(nodes.count, 8)

        if nodes.count == 8 {
            XCTAssertEqual(nodes[0].value, 1)
            XCTAssertEqual(nodes[1].value, 2)
            XCTAssertEqual(nodes[2].value, 1)
            XCTAssertEqual(nodes[3].value, 2)
            XCTAssertEqual(nodes[4].value, 1)
            XCTAssertEqual(nodes[5].value, 2)
            XCTAssertEqual(nodes[6].value, 1)
            XCTAssertEqual(nodes[7].value, 2)
        }
    }
}
