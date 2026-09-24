//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
@preconcurrency import Combine
import _Concurrency
import SwiftAsyncStream

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

                // Combine permits a subscriber to call `request(_:)` more than once (e.g.
                // accumulating demand before any value has arrived); this publisher only ever
                // produces a single value/completion, so a second call while `_task` is already
                // running must not start a second one. Without this guard, two overlapping calls
                // ran `wrapper()` twice -- a real problem for a non-idempotent request -- and
                // could deliver two `receive(_:)`/`receive(completion:)` pairs to one subscriber,
                // violating Combine's at-most-one-completion contract.
                guard _task == nil else {
                    return
                }

                _task = _Concurrency.Task {
                    do {
                        let value = try await wrapper()
                        guard !_Concurrency.Task.isCancelled else { return }
                        _ = subscriber.receive(value)
                        subscriber.receive(completion: .finished)
                    } catch {
                        guard !_Concurrency.Task.isCancelled else { return }
                        subscriber.receive(completion: .failure(error))
                    }
                }
            }
        }

        func cancel() {
            let task = lock.withLock { () -> _Concurrency.Task<Void, Never>? in
                let task = _task
                _subscriber = nil
                _task = nil
                return task
            }

            task?.cancel()
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

    ///
    /// Subscribes the given `Subscriber` to this publisher.
    ///
    /// - Parameter subscriber: The `Subscriber` to receive values and completion.
    ///
    public func receive<S>(
        subscriber: S
    ) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = Subscription(wrapper: wrapper, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    ///
    /// Creates a ``PublishedTask`` publisher from the current ``RequestTask`` instance.
    ///
    /// - Returns: A publisher that emits the output of the current ``RequestTask`` instance.
    ///
    public func publisher() -> PublishedTask<Element> {
        .init(self)
    }
}
#endif
