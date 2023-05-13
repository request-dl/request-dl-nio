/*
 See LICENSE for this package's licensing information.
*/

import Foundation
#if canImport(Combine)
import Combine
import _Concurrency

/**
A publisher that wraps a Task instance and publishes its output asynchronously.
*/
public struct PublishedTask<Output>: Publisher {

    class Subscription<S: Subscriber>: Combine.Subscription where S.Failure == Error {

        // MARK: - Private properties

        private var task: _Concurrency.Task<Void, Never>?
        private var subscriber: S?

        private let wrapper: () async throws -> S.Input

        // MARK: - Inits

        init(
            wrapper: @escaping () async throws -> S.Input,
            subscriber: S
        ) {
            self.wrapper = wrapper
            self.subscriber = subscriber
        }

        // MARK: - Internal properties

        func request(_ demand: Subscribers.Demand) {
            guard let subscriber else {
                return
            }

            task = _Concurrency.Task {
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

    public typealias Failure = Error

    // MARK: - Private properties

    private let wrapper: () async throws -> Output

    // MARK: - Inits

    init<Content: Task>(_ content: Content) where Content.Element == Output {
        self.wrapper = { try await content.result() }
    }

    // MARK: - Public methods

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

// MARK: - Task extension

extension Task {

    /**
     Creates a `PublishedTask` publisher from the current `Task` instance.

     - Returns: A `PublishedTask` publisher that emits the output of the current `Task` instance.
     */
    public func publisher() -> PublishedTask<Element> {
        .init(self)
    }
}
#endif
