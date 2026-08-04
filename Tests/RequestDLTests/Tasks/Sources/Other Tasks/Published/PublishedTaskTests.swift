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
// import struct Foundation.Data
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
}
#endif
