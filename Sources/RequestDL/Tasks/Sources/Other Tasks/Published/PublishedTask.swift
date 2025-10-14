/*
 See LICENSE for this package's licensing information.
*/

import Foundation
#if os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS)
@preconcurrency import Combine
import _Concurrency

/// A publisher for any ``RequestTask``.
public struct PublishedTask<Output: Sendable>: Publisher {

    final class Subscription<S: Subscriber>: @unchecked Sendable, Combine.Subscription where S.Failure == Error {

        // MARK: - Private properties

        private let lock = Lock()
        private let wrapper: () async throws -> S.Input
        
        // MARK: - Unsafe properties
        
        private var _task: _Concurrency.Task<Void, Never>?
        private var _subscriber: S?

        // MARK: - Inits

        init(
            wrapper: @escaping () async throws -> S.Input,
            subscriber: S
        ) {
            self.wrapper = wrapper
            self._subscriber = subscriber
        }

        // MARK: - Internal properties

        func request(_ demand: Subscribers.Demand) {
            lock.withLock {
                guard let subscriber = _subscriber else {
                    return
                }
                
                _task = _Concurrency.Task {
                    do {
                        _ = subscriber.receive(try await wrapper())
                        subscriber.receive(completion: .finished)
                    } catch {
                        subscriber.receive(completion: .failure(error))
                    }
                }
            }
        }

        func cancel() {
            lock.withLock {
                _subscriber = nil
                _task = nil
            }
        }
    }

    public typealias Failure = Error

    // MARK: - Private properties

    private let wrapper: () async throws -> Output

    // MARK: - Inits

    init<Content: RequestTask>(_ content: Content) where Content.Element == Output {
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

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Creates a ``PublishedTask`` publisher from the current ``RequestTask`` instance.

     - Returns: A publisher that emits the output of the current ``RequestTask`` instance.
     */
    public func publisher() -> PublishedTask<Element> {
        .init(self)
    }
}
#endif
