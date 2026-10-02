//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsExecutionObserverTests {

    private typealias Event = Internals.ExecutionObserver.Event

    /// Collects what the observer delivers, and can hold delivery back to model a slow observer.
    private final class Recorder: @unchecked Sendable {

        private let lock = Lock()
        private var _events: [Event] = []
        private var _gate: CheckedContinuation<Void, Never>?
        private var _isHeld = false

        var events: [Event] {
            lock.withLock { _events }
        }

        /// The next delivery waits until ``release()``.
        func hold() {
            lock.withLock { _isHeld = true }
        }

        func release() {
            let gate = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                _isHeld = false
                defer { _gate = nil }
                return _gate
            }

            gate?.resume()
        }

        func record(_ event: Event) async {
            lock.withLock { _events.append(event) }

            await withCheckedContinuation { continuation in
                let shouldWait = lock.withLock { () -> Bool in
                    guard _isHeld else {
                        return false
                    }

                    _gate = continuation
                    return true
                }

                if !shouldWait {
                    continuation.resume()
                }
            }
        }

        var states: [String] {
            events.compactMap {
                if case .state(let state) = $0 {
                    return Self.name(state)
                }

                return nil
            }
        }

        var downloads: [Internals.ExecutionObserver.Transfer] {
            events.compactMap {
                if case .progress(_, let download) = $0 {
                    return download
                }

                return nil
            }
        }

        var uploads: [Internals.ExecutionObserver.Transfer] {
            events.compactMap {
                if case .progress(let upload, _) = $0 {
                    return upload
                }

                return nil
            }
        }

        static func name(_ state: Internals.ExecutionObserver.State) -> String {
            switch state {
            case .started:
                return "started"
            case .suspended:
                return "suspended"
            case .resumed:
                return "resumed"
            case .reconnecting(let attempt):
                return "reconnecting(\(attempt))"
            case .finished:
                return "finished"
            case .failed:
                return "failed"
            }
        }
    }

    private func makeObserver() -> (Internals.ExecutionObserver, Recorder) {
        let recorder = Recorder()
        return (Internals.ExecutionObserver { await recorder.record($0) }, recorder)
    }

    // MARK: - Progress

    @Test
    func progress_isReportedWithItsTotal() async throws {
        // Given
        let (observer, recorder) = makeObserver()
        observer.expectUpload(100)

        // When
        observer.didSend(40)
        try await eventually { recorder.uploads.map(\.total) == [40] }

        observer.didSend(60)
        observer.didReceive(25)

        // Then
        try await eventually { recorder.uploads.map(\.total) == [40, 100] && recorder.downloads.map(\.total) == [25] }

        #expect(recorder.uploads.map(\.bytes) == [40, 60])
        #expect(recorder.uploads.map(\.expected) == [100, 100])
        #expect(recorder.downloads.first?.expected == nil)
    }

    @Test
    func progressBehindASlowObserver_isMergedNotQueued() async throws {
        // Given: an observer stuck on its first delivery.
        let (observer, recorder) = makeObserver()
        recorder.hold()

        observer.didReceive(1)
        try await eventually { recorder.downloads.count == 1 }

        // When: a thousand more arrive meanwhile.
        for _ in 0..<1_000 {
            observer.didReceive(1)
        }

        recorder.release()

        // Then: they arrive as one step, its bytes their sum and its total the latest.
        try await eventually { recorder.downloads.map(\.total).last == 1_001 }

        #expect(recorder.downloads.count == 2)
        #expect(recorder.downloads.map(\.bytes) == [1, 1_000])
    }

    @Test
    func zeroOrNegativeBytes_areNotProgress() async throws {
        // Given
        let (observer, recorder) = makeObserver()

        // When
        observer.didSend(0)
        observer.didReceive(-4)
        observer.didChange(.started)

        // Then
        try await eventually { recorder.events.count == 1 }
        #expect(recorder.downloads.isEmpty)
        #expect(recorder.uploads.isEmpty)
    }

    // MARK: - State

    @Test
    func states_areDeliveredInOrder_aroundTheProgressBetweenThem() async throws {
        // Given
        let (observer, recorder) = makeObserver()

        // When
        observer.didChange(.started)
        observer.didReceive(10)
        observer.didChange(.suspended)
        observer.didReceive(5)
        observer.didChange(.resumed)
        observer.didChange(.finished)

        // Then: progress recorded before a state change is delivered before it.
        try await eventually { recorder.states.last == "finished" }

        #expect(recorder.states == ["started", "suspended", "resumed", "finished"])

        let kinds = recorder.events.map { event -> String in
            switch event {
            case .progress:
                return "progress"
            case .state(let state):
                return Recorder.name(state)
            }
        }

        #expect(kinds == ["started", "progress", "suspended", "progress", "resumed", "finished"])
        #expect(recorder.downloads.map(\.total) == [10, 15])
    }

    @Test
    func repeatedSuspendAndResume_areNotChanges() async throws {
        // Given
        let (observer, recorder) = makeObserver()

        // When
        observer.didChange(.suspended)
        observer.didChange(.suspended)
        observer.didChange(.resumed)
        observer.didChange(.resumed)
        observer.didChange(.finished)

        // Then
        try await eventually { recorder.states.last == "finished" }
        #expect(recorder.states == ["suspended", "resumed", "finished"])
    }

    @Test
    func theFirstEnding_closesTheObserver() async throws {
        // Given
        let (observer, recorder) = makeObserver()

        // When
        observer.didChange(.finished)
        observer.didChange(.failed(CancellationError()))
        observer.didChange(.suspended)
        observer.didReceive(10)
        observer.didSend(10)

        // Then
        try await eventually { recorder.states == ["finished"] }
        try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        #expect(recorder.events.count == 1)
    }

    @Test
    func reconnectionsAreReportedWithTheirNumber() async throws {
        // Given
        let (observer, recorder) = makeObserver()

        // When
        observer.didChange(.reconnecting(attempt: 1))
        observer.didChange(.reconnecting(attempt: 2))

        // Then
        try await eventually { recorder.states.count == 2 }
        #expect(recorder.states == ["reconnecting(1)", "reconnecting(2)"])
    }

    // MARK: - Expected download size

    private func head(_ headers: [(String, String)]) -> Internals.ResponseHead {
        Internals.ResponseHead(
            url: "http://localhost/",
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: 1, major: 1),
            headers: headers.map { .init(name: $0.0, value: $0.1) },
            isKeepAlive: true
        )
    }

    @Test
    func theFirstHeadWins_andALaterOneChangesNothing() async throws {
        // Given
        let (observer, recorder) = makeObserver()

        // When: a head that states a length, then another one (a continuation's, say).
        observer.didReceiveHead(head([("Content-Length", "100")]))
        observer.didReceiveHead(head([("Content-Length", "999")]))
        observer.didReceive(1)

        // Then
        try await eventually { !recorder.downloads.isEmpty }
        #expect(recorder.downloads.first?.expected == 100)
    }

    @Test
    func aHeadAfterTheEnd_isIgnored() async throws {
        // Given
        let (observer, recorder) = makeObserver()
        observer.didChange(.finished)
        try await eventually { recorder.states == ["finished"] }

        // When
        observer.didReceiveHead(head([("Content-Length", "100")]))
        observer.didReceive(1)

        // Then: closed, so neither the size nor the bytes are reported.
        try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        #expect(recorder.downloads.isEmpty)
    }

    @Test(
        arguments: [
            ([("Content-Length", "1234")], 1_234 as Int?),
            ([("Content-Length", "1234"), ("Content-Encoding", "identity")], 1_234),
            ([("Content-Length", "1234"), ("Content-Encoding", "gzip")], nil),
            ([("Content-Length", "1234"), ("Content-Encoding", "identity, br")], nil),
            ([("Transfer-Encoding", "chunked")], nil),
            ([("Content-Length", "10"), ("Content-Length", "20")], nil),
            ([("Content-Length", "7"), ("Content-Length", "7")], 7),
            ([("Content-Length", "soon")], nil),
            ([], nil),
        ] as [([(String, String)], Int?)]
    )
    func expectedDownloadSize_comesFromAHeadThatStatesItForTheBytesCounted(
        headers: [(String, String)],
        expected: Int?
    ) async throws {
        // Given
        let (observer, recorder) = makeObserver()

        // When
        observer.didReceiveHead(head(headers))
        observer.didReceive(1)

        // Then
        try await eventually { !recorder.downloads.isEmpty }
        #expect(recorder.downloads.first?.expected == expected)
    }
}
