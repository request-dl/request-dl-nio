/*
 See LICENSE for this package's licensing information.
*/

import Foundation

class DataStream<Value> {

    private var queue: any StreamQueue<Value>
    private let operationQueue: OperationQueue
    private var isQueueing = false

    init() {
        self.queue = StackStreamQueue()
        self.operationQueue = OperationQueue()

        operationQueue.qualityOfService = .background
        operationQueue.maxConcurrentOperationCount = 1
    }

    func append(_ value: Result<Value, Error>) {
        operationQueue.addOperation {
            switch value {
            case .success(let value):
                self.queue.append(.success(value))
            case .failure(let error):
                self.queue.append(.failure(error))
            }
        }
    }

    func close() {
        operationQueue.addOperation {
            self.queue.append(.success(nil))
        }
    }

    func observe(_ closure: @escaping (Result<Value?, Error>) -> Void) {
        isQueueing = true
        operationQueue.addOperation {
            var queue = self.queue
            var dispatchQueue = DispatchStreamQueue(closure)

            do {
                while let value = try queue.next() {
                    dispatchQueue.append(.success(value))
                }
            } catch {
                dispatchQueue.append(.failure(error))
            }

            if !queue.isOpen && dispatchQueue.isOpen {
                dispatchQueue.append(.success(nil))
            }

            self.queue = dispatchQueue
            self.isQueueing = false
        }
    }
}

protocol StreamQueue<Value> {
    associatedtype Value

    var isOpen: Bool { get }

    mutating func append(_ value: Result<Value?, Error>)

    mutating func next() throws -> Value?
}

struct StackStreamQueue<Value>: StreamQueue {

    private var root: Node?
    private weak var last: Node?
    private var error: Error?
    var isOpen: Bool = true

    init() {}

    mutating func append(_ value: Result<Value?, Error>) {
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

    mutating func next() throws -> Value? {
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

extension StackStreamQueue {

    class Node {
        let value: Value
        var next: Node?

        init(_ value: Value) {
            self.value = value
            self.next = nil
        }
    }
}

struct DispatchStreamQueue<Value>: StreamQueue {

    private var closure: ((Result<Value?, Error>) -> Void)?

    var isOpen: Bool {
        closure != nil
    }

    init(_ closure: @escaping (Result<Value?, Error>) -> Void) {
        self.closure = closure
    }

    mutating func append(_ value: Result<Value?, Error>) {
        guard let closure = closure else {
            return
        }

        switch value {
        case .failure(let failure):
            closure(.failure(failure))
            self.closure = nil
        case .success(let value):
            closure(.success(value))

            if value == nil {
                self.closure = nil
            }
        }
    }

    func next() throws -> Value? {
        nil
    }
}

extension DataStream {

    func asyncStream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { [self] continuation in
            self.observe {
                switch $0 {
                case .failure(let error):
                    continuation.finish(throwing: error)
                case .success(let value):
                    if let value = value {
                        continuation.yield(value)
                    } else {
                        continuation.finish(throwing: nil)
                    }
                }
            }
        }
    }
}
