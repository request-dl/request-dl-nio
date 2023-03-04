//
//  Context.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

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

    private static func make(_ configuration: MakeConfiguration, in node: NodeType) {
        node.fetchObject()?.makeProperty(configuration)

        for node in node.children {
            make(configuration, in: node)
        }
    }

    func make(_ configuration: MakeConfiguration) {
        Self.make(configuration, in: root)
    }
}
