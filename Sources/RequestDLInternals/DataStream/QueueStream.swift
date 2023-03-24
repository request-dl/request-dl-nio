//
//  File.swift
//
//
//  Created by Brenno on 22/03/23.
//

import Foundation

class QueueStream<Value>: StreamProtocol {

    private var root: Node?
    private weak var last: Node?
    private var error: Error?
    var isOpen: Bool = true

    init() {}

    func append(_ value: Result<Value?, Error>) {
        guard isOpen else {
            return
        }

        switch value {
        case .failure(let failure):
            error = failure
            root = nil
            last = nil
            isOpen = false
        case .success(let value):
            guard let value = value else {
                isOpen = false
                return
            }

            let last = last ?? root
            let node = Node(value)
            last?.next = node
            self.last = node
            self.root = root ?? node
        }
    }

    func next() throws -> Value? {
        if let error = error {
            self.error = nil
            throw error
        }

        guard let root = root else {
            return nil
        }

        self.root = root.next
        return root.value
    }
}

extension QueueStream {

    class Node {
        let value: Value
        var next: Node?

        init(_ value: Value) {
            self.value = value
            self.next = nil
        }
    }
}
