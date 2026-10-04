//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLInternals
@testable import RequestDLTestSupport

/// What reaches the execution from one exchange of a resumable upload, and what doesn't.
struct ResumableUploadExchangeRelayTests {

    // MARK: - Private types

    private final class Recording: @unchecked Sendable {

        private let lock = Lock()
        private var _events: [String] = []
        private var _downloaded = 0

        var events: [String] {
            lock.withLock { _events }
        }

        var downloaded: Int {
            lock.withLock { _downloaded }
        }

        func record(_ event: Internals.ExecutionObserver.Event) {
            let name: String

            switch event {
            case .progress(let upload, let download):
                lock.withLock { _downloaded += download?.bytes ?? 0 }
                name = "progress(up: \(upload?.bytes ?? 0), down: \(download?.bytes ?? 0))"
            case .state(.finished):
                name = "finished"
            case .state(.failed):
                name = "failed"
            case .state:
                name = "state"
            }

            lock.withLock { _events.append(name) }
        }
    }

    private static let head = Internals.ResponseHead(
        url: "https://example.com",
        status: .init(code: 200, reason: ""),
        version: .init(minor: 1, major: 1),
        headers: [],
        isKeepAlive: true
    )

    private func makeParent() -> (Internals.TransferControl, Recording) {
        let recording = Recording()
        let observer = Internals.ExecutionObserver { event in
            recording.record(event)
        }

        return (Internals.TransferControl(observer: observer), recording)
    }

    // MARK: - Tests

    @Test
    func sentBytes_alwaysReachTheExecution() async throws {
        // Given
        let (parent, recording) = makeParent()
        let relay = ResumableUploadExchangeRelay(parent: parent)

        // When: bytes of an exchange that is then discarded are on the network all the same.
        relay.control?.observer?.didSend(100)
        try await eventually { recording.events.contains("progress(up: 100, down: 0)") }

        relay.discard()

        // Then
        #expect(recording.events == ["progress(up: 100, down: 0)"])
    }

    @Test
    func aDiscardedExchange_reportsNeitherWhatItReceivedNorHowItEnded() async throws {
        // Given
        let (parent, recording) = makeParent()
        let relay = ResumableUploadExchangeRelay(parent: parent)
        let control = try #require(relay.control)

        // When
        control.observer?.didReceive(50)
        relay.discard()
        control.observer?.didChange(.finished)
        parent.observer?.didSend(1)

        // Then: nothing but what the execution itself recorded.
        try await eventually { recording.events == ["progress(up: 1, down: 0)"] }
        try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        #expect(recording.events == ["progress(up: 1, down: 0)"])
    }

    @Test
    func theFinalExchange_reportsWhatItReceivedBeforeAndAfterBeingDecided_thenHowItEnded() async throws {
        // Given
        let (parent, recording) = makeParent()
        let relay = ResumableUploadExchangeRelay(parent: parent)
        let control = try #require(relay.control)

        // When: some of the body arrives before it is known to be the response of the upload, and
        // the rest, and the end, after.
        control.observer?.didReceive(30)
        try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        relay.decide(final: Self.head)
        control.observer?.didReceive(70)
        control.observer?.didChange(.finished)

        // Then: all of it, and only then the end.
        try await eventually { recording.events.last == "finished" }
        #expect(recording.downloaded == 100)
        #expect(recording.events.filter { $0 == "finished" }.count == 1)
    }

    /// How an exchange ended is delivered after its response was consumed, which is after whoever
    /// drove it has let go of the relay. It has to still reach the execution.
    @Test
    func theEnd_isDeliveredEvenIfNothingHoldsTheRelayAnymore() async throws {
        // Given
        let (parent, recording) = makeParent()
        var relay: ResumableUploadExchangeRelay? = ResumableUploadExchangeRelay(parent: parent)
        let control = try #require(relay?.control)

        relay?.decide(final: Self.head)

        // When
        relay = nil
        control.observer?.didChange(.finished)

        // Then
        try await eventually { recording.events.contains("finished") }
        #expect(recording.events.contains("finished"))
    }

    @Test
    func theExchange_followsTheSuspensionOfTheExecution_untilItIsOver() async throws {
        // Given
        let (parent, _) = makeParent()
        let relay = ResumableUploadExchangeRelay(parent: parent)
        let control = try #require(relay.control)

        // When
        parent.suspend()

        // Then
        #expect(control.isSuspended)

        // When: the exchange is over, so what the execution does is no longer its business.
        relay.discard()
        parent.resume()

        // Then
        #expect(control.isSuspended)
        #expect(relay.control == nil)
    }
}
