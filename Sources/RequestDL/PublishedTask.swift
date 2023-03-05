//
//  PublishedTask.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
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
import Combine
import SwiftUI

/**
A publisher that wraps a Task instance and publishes its output asynchronously.
*/
public struct PublishedTask<Output>: Publisher {

    public typealias Failure = Error

    private let wrapper: () async throws -> Output

    init<Content: Task>(_ content: Content) where Content.Element == Output {
        self.wrapper = { try await content.response() }
    }

    /**
     Subscribes the given `Subscriber` to this publisher.

     - Parameter subscriber: The `Subscriber` to receive values and completion.
     */
    public func receive<S>(
        subscriber: S
    ) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = Subscription(wrapper: wrapper, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }
}

extension PublishedTask {

    class Subscription<S: Subscriber>: Combine.Subscription where S.Failure == Error {

        private var task: SwiftUI.Task<Void, Never>?

        private let wrapper: () async throws -> S.Input
        private var subscriber: S?

        init(
            wrapper: @escaping () async throws -> S.Input,
            subscriber: S
        ) {
            self.wrapper = wrapper
            self.subscriber = subscriber
        }

        func request(_ demand: Subscribers.Demand) {
            guard let subscriber else {
                return
            }

            task = SwiftUI.Task {
                do {
                    _ = subscriber.receive(try await wrapper())
                    subscriber.receive(completion: .finished)
                } catch {
                    subscriber.receive(completion: .failure(error))
                }
            }
        }

        func cancel() {
            subscriber = nil
            task = nil
        }
    }
}

extension Task {

    /**
     Creates a `PublishedTask` publisher from the current `Task` instance.

     - Returns: A `PublishedTask` publisher that emits the output of the current `Task` instance.
     */
    public func publisher() -> PublishedTask<Element> {
        .init(self)
    }
}
