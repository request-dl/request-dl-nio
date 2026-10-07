//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Crypto
import Foundation
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// Pausing, resuming and continuing a background download, against a real socket server.
///
/// The background session itself can't be started from this bare SwiftPM test harness (see
/// `BackgroundDownloadTaskTests`), so everything that does not need it runs here against an
/// ordinary session: what picks the right task, what a failed download's error carries, what
/// cancelling produces, and the task that continues a download from it. They are the same code
/// the background session runs; only the configuration of the session differs.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct BackgroundDownloadResumptionTests {

    private static let length = 64 * 1_048_576

    // MARK: - Helpers

    /// What an ordinary session's delegate says about one download.
    private final class Observer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

        private let lock = Lock()
        private var _written: Int64 = 0
        private var _file: URL?
        private var _error: (any Error)?
        private var _isOver = false
        private var _isHeld = false
        private let suspendAfter: Int64?

        init(suspendAfter: Int64? = nil) {
            self.suspendAfter = suspendAfter
        }

        var written: Int64 { lock.withLock { _written } }
        var file: URL? { lock.withLock { _file } }
        var error: (any Error)? { lock.withLock { _error } }
        var isOver: Bool { lock.withLock { _isOver } }

        /// Whether `suspendAfter` was reached and the task is already suspended. It is only set
        /// once `suspend()` has returned: a test that acts on the task as soon as `written` crosses
        /// the threshold would otherwise do it concurrently with that very `suspend()`.
        var isHeld: Bool { lock.withLock { _isHeld } }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            lock.withLock { _written = totalBytesWritten }

            // Callbacks arrive serially, so this suspends exactly once: `suspend()` nests, and a
            // second call would need a second `resume()` to undo.
            if let suspendAfter, totalBytesWritten >= suspendAfter, !isHeld {
                downloadTask.suspend()
                lock.withLock { _isHeld = true }
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            let kept = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString)
            try? FileManager.default.moveItem(at: location, to: kept)
            lock.withLock { _file = kept }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            lock.withLock {
                _error = error
                _isOver = true
            }
        }
    }

    /// A protocol that takes every request and never answers it, leaving the task in flight.
    private final class PendingURLProtocol: URLProtocol {

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {}
        override func stopLoading() {}
    }

    /// Whether `file` is the resource the server serves, whole and in order.
    private static func isTheWholeResource(_ file: URL?, seed: Int = 0) -> Bool {
        guard
            let file,
            let handle = try? FileHandle(forReadingFrom: file),
            let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int,
            size == length
        else {
            return false
        }

        defer { try? handle.close() }

        var position = 0

        while position < size {
            let count = min(TransferServer.maximumPiece, size - position)

            guard
                let chunk = try? handle.read(upToCount: count),
                chunk.count == count,
                chunk.elementsEqual(TransferServer.body(from: position, count: count, seed: seed))
            else {
                return false
            }

            position += count
        }

        return true
    }

    private static func url(_ server: TransferServer) -> URL {
        URL(string: "http://127.0.0.1:\(server.port)/resource")!
    }

    // MARK: - What a failed download carries

    @Test
    func resumeData_isReadFromTheUserInfoOfAnError() {
        // Given
        let data = Data([1, 2, 3])
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: [NSURLSessionDownloadTaskResumeData: data]
        )

        // Then
        #expect(BackgroundDownloads.resumeData(from: error)?.data == data)
    }

    @Test
    func resumeData_isReadFromAURLError() {
        // Given
        let data = Data([4, 5, 6])
        let error = URLError(.networkConnectionLost, userInfo: [NSURLSessionDownloadTaskResumeData: data])

        // Then
        #expect(BackgroundDownloads.resumeData(from: error)?.data == data)
    }

    @Test
    func resumeData_isNilWhenTheErrorCarriesNone() {
        struct Failure: Error {}

        #expect(BackgroundDownloads.resumeData(from: URLError(.cancelled)) == nil)
        #expect(BackgroundDownloads.resumeData(from: Failure()) == nil)
    }

    @Test
    func resumeData_survivesBeingKept() throws {
        // Given
        let data = BackgroundDownloadResumeData(data: Data([7, 8, 9]))

        // When
        let kept = try JSONDecoder().decode(BackgroundDownloadResumeData.self, from: JSONEncoder().encode(data))

        // Then
        #expect(kept == data)
    }

    // MARK: - Pausing and resuming

    @Test
    func suspendAndResume_actOnTheDownloadWithThatID_andOnNoOtherOne() async throws {
        // Given: two downloads, made as the background session makes them, neither started.
        // A request that is never answered, so `wanted` is still running when it is looked at.
        // Pointing it at a closed port instead has the connection refused at once, and a task
        // that already failed is neither `.running` nor, once suspended, `.suspended`.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingURLProtocol.self]

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let url = URL(string: "http://127.0.0.1:1/resource")!

        let wanted = session.downloadTask(with: url)
        wanted.taskDescription = BackgroundDownloads.Session.encode(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/42")
        )

        let other = session.downloadTask(with: url)
        other.taskDescription = BackgroundDownloads.Session.encode(
            id: "episode-43",
            destination: URL(fileURLWithPath: "/tmp/43")
        )

        defer {
            wanted.cancel()
            other.cancel()
        }

        let match = try #require(BackgroundDownloads.Session.firstTask(matching: "episode-42", in: [other, wanted]))
        #expect(match === wanted)

        // When
        BackgroundDownloads.Session.apply(.resume, to: match)

        // Then: the state a task reports is not updated in the same call that asked for it, so
        // wait for it instead of reading it back at once (`.suspend` was seen still reporting
        // `.running` on a CI runner).
        try await eventually(timeout: 10) { wanted.state == .running }
        #expect(other.state == .suspended)

        // When
        BackgroundDownloads.Session.apply(.suspend, to: match)

        // Then
        try await eventually(timeout: 10) { wanted.state == .suspended }
    }

    @Test
    func suspendAndResume_findNothingWhenNoDownloadWasEverScheduled() async {
        // There is no background session to ask in this process, so there is nothing to find.
        #expect(await BackgroundDownloads.suspend(id: "nothing") == false)
        #expect(await BackgroundDownloads.resume(id: "nothing") == false)
        #expect(await BackgroundDownloads.cancelProducingResumeData(id: "nothing") == nil)
    }

    // MARK: - Continuing a download

    @Test
    func aDownloadThatLostItsConnection_carriesWhatItTakesToContinueIt() async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: a connection cut a few megabytes in.
            server.dropPlan = [6 * 1_048_576]
            let observer = Observer()
            let session = URLSession(configuration: .ephemeral, delegate: observer, delegateQueue: nil)
            defer { session.invalidateAndCancel() }

            // When
            session.downloadTask(with: Self.url(server)).resume()
            try await eventually(timeout: 120) { observer.isOver }

            // Then: the error says what it takes, and the download can be continued from it.
            let error = try #require(observer.error)
            let resumeData = try #require(BackgroundDownloads.resumeData(from: error))

            let resumed = Observer()
            let resumedSession = URLSession(configuration: .ephemeral, delegate: resumed, delegateQueue: nil)
            defer { resumedSession.invalidateAndCancel() }

            let task = BackgroundDownloads.Session.makeTask(
                in: resumedSession,
                resumingFrom: resumeData,
                description: BackgroundDownloads.Session.encode(
                    id: "episode-42",
                    destination: URL(fileURLWithPath: "/tmp/42")
                )
            )

            #expect(BackgroundDownloads.Session.decode(task.taskDescription)?.id == "episode-42")

            task.resume()
            try await eventually(timeout: 120) { resumed.isOver }

            #expect(resumed.error == nil)
            #expect(Self.isTheWholeResource(resumed.file))

            // The second request asked for the rest, with `Range`, and did not start over.
            try await eventually(timeout: 30) { server.requests.count >= 2 }
            #expect(server.requests.last?.header("Range") != nil)
        }
    }

    @Test
    func cancellingADownload_producesWhatItTakesToContinueIt() async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: a download held still a few megabytes in.
            let observer = Observer(suspendAfter: 2 * 1_048_576)
            let session = URLSession(configuration: .ephemeral, delegate: observer, delegateQueue: nil)
            defer { session.invalidateAndCancel() }

            let task = session.downloadTask(with: Self.url(server))
            task.resume()
            try await eventually(timeout: 120) { observer.isHeld }

            // When
            let resumeData = try #require(await BackgroundDownloads.Session.cancelProducingResumeData(of: task))

            // Then: cancelled, and continued from what it produced to the whole resource.
            try await eventually(timeout: 30) { observer.isOver }
            #expect((observer.error as? URLError)?.code == .cancelled)

            let resumed = Observer()
            let resumedSession = URLSession(configuration: .ephemeral, delegate: resumed, delegateQueue: nil)
            defer { resumedSession.invalidateAndCancel() }

            BackgroundDownloads.Session.makeTask(in: resumedSession, resumingFrom: resumeData, description: nil)
                .resume()

            try await eventually(timeout: 120) { resumed.isOver }

            #expect(resumed.error == nil)
            #expect(Self.isTheWholeResource(resumed.file))
        }
    }

    @Test
    func aResourceThatChanged_isStartedOverByTheSystem_notSplicedOnto() async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: a download held still, cancelled for its resume data, and a server that now
            // holds another version of the resource.
            let observer = Observer(suspendAfter: 2 * 1_048_576)
            let session = URLSession(configuration: .ephemeral, delegate: observer, delegateQueue: nil)
            defer { session.invalidateAndCancel() }

            let task = session.downloadTask(with: Self.url(server))
            task.resume()
            try await eventually(timeout: 120) { observer.isHeld }

            let resumeData = try #require(await BackgroundDownloads.Session.cancelProducingResumeData(of: task))
            server.resource = .init(length: Self.length, seed: 7, validator: .entityTag("\"v2\""))

            // When
            let resumed = Observer()
            let resumedSession = URLSession(configuration: .ephemeral, delegate: resumed, delegateQueue: nil)
            defer { resumedSession.invalidateAndCancel() }

            BackgroundDownloads.Session.makeTask(in: resumedSession, resumingFrom: resumeData, description: nil)
                .resume()

            try await eventually(timeout: 120) { resumed.isOver }

            // Then: what URLSession hands over is the whole new resource, and never a mix of the
            // two. (It starts over by itself, as `ChangedDownloadBehavior.restart` does.)
            #expect(resumed.error == nil)
            #expect(Self.isTheWholeResource(resumed.file, seed: 7))
        }
    }

    // MARK: - The task

    @Test
    func aTaskThatContinuesADownload_isRefusedForTheSameConfigurationsAsAnyOther() async throws {
        // Given: valid, complete, in-memory bytes rather than a file path.
        let client = Certificates().client()
        let certificateBytes = try [UInt8](Data(contentsOf: client.certificateURL))
        let privateKeyBytes = try [UInt8](Data(contentsOf: client.privateKeyURL))

        let task = BackgroundDownloadTask(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3"),
            resumingFrom: BackgroundDownloadResumeData(data: Data([1]))
        ) {
            BaseURL("localhost")

            SecureConnection {
                RequestDL.Certificates(certificateBytes)
                PrivateKey(privateKeyBytes)
            }
        }

        // When / Then
        await #expect(throws: BackgroundDownloadUnsupportedConfigurationError.self) {
            try await task.result()
        }
    }
}

#endif
