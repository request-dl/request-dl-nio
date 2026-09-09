//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

import Foundation

/// Covers `BackgroundDownloads.Session`'s `URLSessionDownloadDelegate` callbacks directly, against
/// a task built from an ordinary (non-background) `URLSession.shared` -- never resumed, only ever
/// used as a way to get a real `URLSessionDownloadTask` object to set `taskDescription` on and
/// hand to the delegate method by hand. This exercises the same code a real background transfer
/// would run through, without starting one: this SwiftPM test harness has none of the entitlements
/// a real background session needs to actually schedule anything (the same gap already documented
/// for Keychain-backed mTLS), so this is the ceiling of what can be verified here -- see
/// `BackgroundDownloadTaskTests`'s own doc comment for the same reasoning applied to `result()`.
///
/// Every delegate method under test is synchronous by contract (that's the whole reason `Session`
/// isn't an `actor` -- see its own doc comment), so every assertion below runs immediately after
/// the call that's supposed to have triggered it, with no `await`/polling needed. Every test also
/// builds its own `BackgroundDownloads.Session()` rather than reusing `.shared`, so `onEvent`
/// assertions never race another test's.
struct BackgroundDownloadsSessionDelegateTests {

    // MARK: - didFinishDownloadingTo

    @Test
    func didFinishDownloadingTo_whenTaskDescriptionValid_movesFileToDestinationAndReportsCompleted() async throws {
        try await withTemporaryFileURL("source.tmp") { location in
            try await withTemporaryFileURL("destination.bin") { destination in
                // Given
                try Data("downloaded content".utf8).write(to: location)

                let session = BackgroundDownloads.Session()
                let events = EventBox()
                session.onEvent = { events.append($0) }

                let task = URLSession.shared.downloadTask(with: try #require(URL(string: "https://example.com")))
                task.taskDescription = BackgroundDownloads.Session.encode(id: "episode-42", destination: destination)

                // When
                session.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: location)

                // Then
                #expect(try Data(contentsOf: destination) == Data("downloaded content".utf8))
                #expect(!FileManager.default.fileExists(atPath: location.path))

                let recorded = events.all
                #expect(recorded.count == 1)

                guard case .completed(let id, let recordedDestination) = try #require(recorded.first) else {
                    Issue.record("Expected .completed, got \(String(describing: recorded.first))")
                    return
                }
                #expect(id == "episode-42")
                #expect(recordedDestination == destination)
            }
        }
    }

    @Test
    func didFinishDownloadingTo_whenDestinationAlreadyExists_overwritesIt() async throws {
        try await withTemporaryFileURL("source.tmp") { location in
            try await withTemporaryFileURL("destination.bin") { destination in
                // Given -- `withTemporaryFileURL` itself already creates an empty file at
                // `destination`, so this is already exercising the overwrite path; write
                // something recognizable there first to make sure it really gets replaced, not
                // just left alone as "already existing."
                try Data("stale content".utf8).write(to: destination)
                try Data("fresh content".utf8).write(to: location)

                let session = BackgroundDownloads.Session()

                let task = URLSession.shared.downloadTask(with: try #require(URL(string: "https://example.com")))
                task.taskDescription = BackgroundDownloads.Session.encode(id: "episode-42", destination: destination)

                // When
                session.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: location)

                // Then
                #expect(try Data(contentsOf: destination) == Data("fresh content".utf8))
            }
        }
    }

    @Test
    func didFinishDownloadingTo_whenSourceFileIsMissing_reportsFailed() async throws {
        try await withTemporaryFileURL("destination.bin") { destination in
            // Given -- `location` deliberately never gets a file written to it, so `moveItem`
            // has nothing to move.
            let missingLocation = temporaryDirectoryURL.appendingPathComponent("RequestDL.\(UUID()).missing")

            let session = BackgroundDownloads.Session()
            let events = EventBox()
            session.onEvent = { events.append($0) }

            let task = URLSession.shared.downloadTask(with: try #require(URL(string: "https://example.com")))
            task.taskDescription = BackgroundDownloads.Session.encode(id: "episode-42", destination: destination)

            // When
            session.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: missingLocation)

            // Then
            let recorded = events.all
            #expect(recorded.count == 1)

            guard case .failed(let id, let recordedDestination, _) = try #require(recorded.first) else {
                Issue.record("Expected .failed, got \(String(describing: recorded.first))")
                return
            }
            #expect(id == "episode-42")
            #expect(recordedDestination == destination)
        }
    }

    @Test
    func didFinishDownloadingTo_whenTaskDescriptionMissing_doesNothing() async throws {
        try await withTemporaryFileURL("source.tmp") { location in
            // Given -- no `taskDescription` set at all, the shape a task RequestDL didn't create
            // would have.
            try Data("content".utf8).write(to: location)

            let session = BackgroundDownloads.Session()
            let events = EventBox()
            session.onEvent = { events.append($0) }

            let task = URLSession.shared.downloadTask(with: try #require(URL(string: "https://example.com")))

            // When
            session.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: location)

            // Then -- neither reported nor moved; this task simply isn't this delegate's to
            // handle.
            #expect(events.all.isEmpty)
            #expect(FileManager.default.fileExists(atPath: location.path))
        }
    }

    // MARK: - didWriteData

    @Test
    func didWriteData_reportsProgressWithRunningTotals() async throws {
        try await withTemporaryFileURL("destination.bin") { destination in
            // Given
            let session = BackgroundDownloads.Session()
            let events = EventBox()
            session.onEvent = { events.append($0) }

            let task = URLSession.shared.downloadTask(with: try #require(URL(string: "https://example.com")))
            task.taskDescription = BackgroundDownloads.Session.encode(id: "episode-42", destination: destination)

            // When
            session.urlSession(
                .shared,
                downloadTask: task,
                didWriteData: 1_024,
                totalBytesWritten: 4_096,
                totalBytesExpectedToWrite: 16_384
            )

            // Then -- the running totals, not the size of this one callback.
            let recorded = events.all
            #expect(recorded.count == 1)

            guard
                case .progress(let id, let recordedDestination, let bytesWritten, let totalBytesExpected) =
                    try #require(recorded.first)
            else {
                Issue.record("Expected .progress, got \(String(describing: recorded.first))")
                return
            }
            #expect(id == "episode-42")
            #expect(recordedDestination == destination)
            #expect(bytesWritten == 4_096)
            #expect(totalBytesExpected == 16_384)
        }
    }

    // MARK: - didCompleteWithError

    @Test
    func didCompleteWithError_whenErrorPresent_reportsFailed() async throws {
        try await withTemporaryFileURL("destination.bin") { destination in
            // Given
            struct SomeError: Error {}

            let session = BackgroundDownloads.Session()
            let events = EventBox()
            session.onEvent = { events.append($0) }

            let task = URLSession.shared.downloadTask(with: try #require(URL(string: "https://example.com")))
            task.taskDescription = BackgroundDownloads.Session.encode(id: "episode-42", destination: destination)

            // When
            session.urlSession(.shared, task: task, didCompleteWithError: SomeError())

            // Then
            let recorded = events.all
            #expect(recorded.count == 1)

            guard case .failed(let id, let recordedDestination, let error) = try #require(recorded.first) else {
                Issue.record("Expected .failed, got \(String(describing: recorded.first))")
                return
            }
            #expect(id == "episode-42")
            #expect(recordedDestination == destination)
            #expect(error is SomeError)
        }
    }

    /// The delegate also fires this on success, with `error == nil` -- must not double-report on
    /// top of `didFinishDownloadingTo`'s own `.completed` event.
    @Test
    func didCompleteWithError_whenErrorIsNil_reportsNothing() async throws {
        try await withTemporaryFileURL("destination.bin") { destination in
            // Given
            let session = BackgroundDownloads.Session()
            let events = EventBox()
            session.onEvent = { events.append($0) }

            let task = URLSession.shared.downloadTask(with: try #require(URL(string: "https://example.com")))
            task.taskDescription = BackgroundDownloads.Session.encode(id: "episode-42", destination: destination)

            // When
            session.urlSession(.shared, task: task, didCompleteWithError: nil)

            // Then
            #expect(events.all.isEmpty)
        }
    }

    // MARK: - handleEvents / urlSessionDidFinishEvents

    @Test
    func handleEvents_whenIdentifierMatches_storesHandlerAndFinishEventsCallsAndClearsIt() async throws {
        // Given
        let session = BackgroundDownloads.Session()
        let firstCalled = CallBox()

        session.handleEvents(forIdentifier: BackgroundDownloads.Session.identifier) {
            firstCalled.markCalled()
        }

        // When
        session.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)

        // Then
        #expect(firstCalled.wasCalled)

        // And -- a second finish-events call with no new `handleEvents` in between must not
        // re-invoke a stale handler.
        let secondCalled = CallBox()
        session.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        #expect(!secondCalled.wasCalled)
    }

    @Test
    func handleEvents_whenIdentifierDoesNotMatch_neverStoresHandler() async throws {
        // Given
        let session = BackgroundDownloads.Session()
        let called = CallBox()

        // When
        session.handleEvents(forIdentifier: "some.other.session") {
            called.markCalled()
        }
        session.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)

        // Then
        #expect(!called.wasCalled)
    }
}

// MARK: - Test helpers

/// Both helpers below are plain, lock-backed classes, not actors -- every callback under test
/// (`onEvent`, `handleEvents`'s `completionHandler`) is synchronous by contract, so an `actor`
/// would force an `await` onto assertions that need to run immediately, not after a hop.
private final class EventBox: @unchecked Sendable {

    private let lock = Lock()
    private var _all: [BackgroundDownloads.Event] = []

    var all: [BackgroundDownloads.Event] {
        lock.withLock { _all }
    }

    func append(_ event: BackgroundDownloads.Event) {
        lock.withLock { _all.append(event) }
    }
}

private final class CallBox: @unchecked Sendable {

    private let lock = Lock()
    private var _wasCalled = false

    var wasCalled: Bool {
        lock.withLock { _wasCalled }
    }

    func markCalled() {
        lock.withLock { _wasCalled = true }
    }
}

#endif
