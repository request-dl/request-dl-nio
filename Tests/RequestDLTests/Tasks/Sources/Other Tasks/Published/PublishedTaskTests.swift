//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

#if canImport(Combine)
import Combine
@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct PublishedTaskTests {

    enum PublisherResult {
        case success
        case failure
    }

    struct PublisherError: Error {}

    @Test
    func successPublisher() async throws {
        // Given
        var cancellation = Set<AnyCancellable>()
        var isSuccess = false
        let expectation = AsyncSignal()

        // When
        MockedTask {
            BaseURL("localhost")
        }
        .collectData()
        .publisher()
        .map { _ in
            PublisherResult.success
        }
        .replaceError(with: .failure)
        .sink {
            isSuccess = $0 == .success
            expectation.signal()
        }.store(in: &cancellation)

        try await expectation.wait()

        // Then
        #expect(isSuccess)
    }

    @Test
    func multiplePublishes() async throws {
        // Given
        let subject = PassthroughSubject<Void, Never>()
        var cancellation = Set<AnyCancellable>()
        var isSuccess = true
        let expectation = AsyncSignal()

        // When
        subject
            .flatMap {
                MockedTask {
                    BaseURL("localhost")
                }
                .collectData()
                .publisher()
                .map { _ in
                    PublisherResult.success
                }
                .replaceError(with: .failure)
            }
            .sink {
                isSuccess = isSuccess && $0 == .success
                expectation.signal()
            }.store(in: &cancellation)

        subject.send()

        try await expectation.wait()

        // Then
        #expect(isSuccess)
    }

    @Test
    func failurePublisher() async throws {
        // Given
        let error = PublisherError()
        var cancellation = Set<AnyCancellable>()
        var receivedFailure = false
        let expectation = AsyncSignal()

        // When
        MockedTask {
            BaseURL("localhost")
        }
        .flatMap { _ in throw error }
        .publisher()
        .sink(
            receiveCompletion: { completion in
                if case .failure = completion {
                    receivedFailure = true
                }
                expectation.signal()
            },
            receiveValue: { _ in }
        ).store(in: &cancellation)

        try await expectation.wait()

        // Then
        #expect(receivedFailure)
    }

    @Test
    func cancelStopsSubscription() async throws {
        // Given
        let cancellable = MockedTask {
            BaseURL("localhost")
        }
        .collectData()
        .publisher()
        .sink(
            receiveCompletion: { _ in },
            receiveValue: { _ in }
        )

        // When / Then
        cancellable.cancel()
    }

    // Regression test: `Subscription.cancel()` used to only drop the `_task`/`_subscriber`
    // references without calling `_task?.cancel()`. Dropping a `_Concurrency.Task` handle does
    // not cancel it, so the wrapped request kept running to completion, and the subscriber —
    // captured directly by the task's closure, not through `_subscriber` — still received a
    // late value/completion after the subscription had already been cancelled, violating
    // Combine's `Subscription.cancel()` contract.
    @Test
    func cancelStopsDeliveryOfAnInFlightRequest() async throws {
        // Given
        let valueReceived = InlineProperty(wrappedValue: false)
        let completionReceived = InlineProperty(wrappedValue: false)

        let cancellable = MockedTask(delay: .milliseconds(200)) {
            BaseURL("localhost")
        }
        .collectData()
        .publisher()
        .sink(
            receiveCompletion: { _ in completionReceived.wrappedValue = true },
            receiveValue: { _ in valueReceived.wrappedValue = true }
        )

        // When
        cancellable.cancel()
        try await _Concurrency.Task.sleep(nanoseconds: 400_000_000)

        // Then
        #expect(!valueReceived.wrappedValue)
        #expect(!completionReceived.wrappedValue)
    }

    // Exercises the `guard let subscriber else { return }` branch in
    // `PublishedTask.Subscription.request(_:)`: a subscriber that cancels its subscription
    // before ever requesting demand leaves `_subscriber` `nil`, so the follow-up `request(_:)`
    // call has to no-op instead of running the wrapped task.
    final class CancelBeforeRequestSubscriber<Input: Sendable>: Subscriber, @unchecked Sendable {
        typealias Failure = Error

        let onValue: @Sendable (Input) -> Void
        let onCompletion: @Sendable (Subscribers.Completion<Error>) -> Void

        init(
            onValue: @escaping @Sendable (Input) -> Void,
            onCompletion: @escaping @Sendable (Subscribers.Completion<Error>) -> Void
        ) {
            self.onValue = onValue
            self.onCompletion = onCompletion
        }

        func receive(subscription: Subscription) {
            subscription.cancel()
            subscription.request(.unlimited)
        }

        func receive(_ input: Input) -> Subscribers.Demand {
            onValue(input)
            return .none
        }

        func receive(completion: Subscribers.Completion<Error>) {
            onCompletion(completion)
        }
    }

    @Test
    func requestAfterCancelDoesNothing() throws {
        // Given
        let valueReceived = InlineProperty(wrappedValue: false)
        let completionReceived = InlineProperty(wrappedValue: false)

        let subscriber = CancelBeforeRequestSubscriber<TaskResult<Data>>(
            onValue: { _ in valueReceived.wrappedValue = true },
            onCompletion: { _ in completionReceived.wrappedValue = true }
        )

        // When
        //
        // `receive(subscription:)` runs synchronously as part of `subscribe(_:)`, and this
        // subscriber cancels before requesting demand — the guard in `request(_:)` returns
        // before any async work is scheduled, so there is nothing to await.
        MockedTask {
            BaseURL("localhost")
        }
        .collectData()
        .publisher()
        .subscribe(subscriber)

        // Then
        #expect(!valueReceived.wrappedValue)
        #expect(!completionReceived.wrappedValue)
    }

    /// Combine explicitly permits a subscriber to call `request(_:)` more than once before any
    /// value has arrived (accumulating demand). `Subscription.request(_:)` used to unconditionally
    /// launch a new `_Concurrency.Task` on every call, overwriting (not cancelling) any prior
    /// in-flight one -- so two overlapping `request(_:)` calls ran the wrapped task twice, a real
    /// problem for a non-idempotent request, and could have delivered two
    /// `receive(_:)`/`receive(completion:)` pairs to one subscriber.
    final class TwiceRequestingSubscriber<Input: Sendable>: Subscriber, @unchecked Sendable {
        typealias Failure = Error

        let onCompletion: @Sendable () -> Void

        init(onCompletion: @escaping @Sendable () -> Void) {
            self.onCompletion = onCompletion
        }

        func receive(subscription: Subscription) {
            subscription.request(.max(1))
            subscription.request(.max(1))
        }

        func receive(_ input: Input) -> Subscribers.Demand {
            .none
        }

        func receive(completion: Subscribers.Completion<Error>) {
            onCompletion()
        }
    }

    @Test
    func requestCalledTwiceBeforeCompletion_onlyExecutesWrappedTaskOnce() async throws {
        // Given
        let counter = ExecutionCounter()
        let expectation = AsyncSignal()

        let subscriber = TwiceRequestingSubscriber<TaskResult<Data>>(
            onCompletion: { expectation.signal() }
        )

        // When
        MockedTask(delay: .milliseconds(100)) {
            BaseURL("localhost")
        }
        .collectData()
        .flatMap { result -> TaskResult<Data> in
            await counter.increment()
            return try result.get()
        }
        .publisher()
        .subscribe(subscriber)

        try await expectation.wait()

        // Gives a spurious second execution (the bug this guards against) a chance to also
        // complete before asserting the final count.
        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

        // Then
        #expect(await counter.value == 1)
    }
}

private actor ExecutionCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    var value: Int {
        count
    }
}
#endif
