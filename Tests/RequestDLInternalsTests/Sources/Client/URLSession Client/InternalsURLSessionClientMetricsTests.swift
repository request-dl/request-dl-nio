//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation

/// What `Internals.URLSessionClient` reports in `SessionTask.metrics`: the transactions
/// `URLSessionTaskMetrics` measured, converted by `Internals.TransactionMetrics.init(_:)`.
///
/// The first test is also the proof that `bytes(for:delegate:)`, which owns the task, still hands
/// `didFinishCollecting` to `TaskDelegate`: without it, nothing here would ever be recorded.
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsURLSessionClientMetricsTests {

    @Test
    func sessionTask_whenResponseDrained_reportsTheTransactionURLSessionMeasured() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "metrics"), at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        // When
        let sessionTask = try await execute(client, url: url)
        let collector = try #require(sessionTask.metrics)

        try await drain(sessionTask)
        try await eventually { !collector.transactions().isEmpty }

        // Then
        let transactions = collector.transactions()
        #expect(transactions.count == 1)

        let transaction = try #require(transactions.first)
        #expect(transaction.url == url)

        let fetchStart = try #require(transaction.fetchStart)
        let requestStart = try #require(transaction.requestStart)
        let requestEnd = try #require(transaction.requestEnd)
        let responseStart = try #require(transaction.responseStart)
        let responseEnd = try #require(transaction.responseEnd)

        #expect(fetchStart <= requestStart)
        #expect(requestStart <= requestEnd)
        #expect(requestEnd <= responseStart)
        #expect(responseStart <= responseEnd)

        #expect(transaction.queued == nil)
        #expect(transaction.error == nil)
        #expect((transaction.responseBodyBytesReceived ?? 0) > 0)

        let connection = try #require(transaction.connection)
        #expect(connection.isReused == false)
        #expect(connection.tlsVersion != nil)
        #expect(connection.remotePort == url.port)
        #expect(connection.negotiatedProtocol != nil)

        // A fresh connection went through every phase that establishes one.
        let connect = try #require(connection.connect)
        let secureConnection = try #require(connection.secureConnection)
        #expect(connect.start <= connect.end)
        #expect(secureConnection.start <= secureConnection.end)
    }

    @Test
    func sessionTask_whenSecondRequestSharesTheSession_reportsTheConnectionAsReused() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "metrics"), at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        // When
        let first = try await execute(client, url: url)
        try await drain(first)

        let second = try await execute(client, url: url)
        let collector = try #require(second.metrics)

        try await drain(second)
        try await eventually { !collector.transactions().isEmpty }

        // Then
        let connection = try #require(collector.transactions().first?.connection)
        #expect(connection.isReused == true)
        #expect(connection.domainLookup == nil)
        #expect(connection.connect == nil)
        #expect(connection.secureConnection == nil)
    }

    @Test
    func sessionTask_whenAnsweredFromURLSessionCache_reportsNoConnection() async throws {
        // Given: the first request leaves a cacheable response behind, which the second one,
        // allowed to use the cache, is answered from.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "metrics"), at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        let first = try await execute(client, url: url, cachePolicy: .useProtocolCachePolicy)
        try await drain(first)

        // When
        let second = try await execute(client, url: url, cachePolicy: .returnCacheDataElseLoad)
        let collector = try #require(second.metrics)

        try await drain(second)
        try await eventually { !collector.transactions().isEmpty }

        // Then: nothing went over the wire, so there is no connection to describe.
        let transaction = try #require(collector.transactions().first)
        #expect(transaction.connection == nil)
    }

    @Test
    func sessionTask_whenRedirectFollowed_reportsOneTransactionPerHop() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let destination = "/" + UUID().uuidString

        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": destination], data: Data()),
            at: origin
        )
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "metrics"), at: destination)

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: destination)
        }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(origin)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .follow(max: 5, allowCycles: false)
        )

        // When
        let sessionTask = try await execute(client, url: url)
        let collector = try #require(sessionTask.metrics)

        try await drain(sessionTask)
        try await eventually { collector.transactions().count == 2 }

        // Then: in the order they happened, each one on the URL it was sent to.
        let transactions = collector.transactions()
        #expect(transactions.map(\.url?.path) == [origin, destination])
    }

    @Test
    func sessionTask_whenConnectionRefused_recordsTheErrorOnTheTransaction() async throws {
        // Given: a port that refuses connections.
        let refused = try RefusedPort()
        defer { refused.release() }
        let port = refused.port

        let url = try #require(URL(string: "http://127.0.0.1:\(port)/resource"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        // When
        let sessionTask = try await execute(client, url: url)
        let collector = try #require(sessionTask.metrics)

        var failed = false

        do {
            try await drain(sessionTask)
        } catch {
            failed = true
        }

        // Then: the exchange never had a task to attribute the error to when it failed, and still
        // ends up on its own transaction.
        try await eventually { collector.transactions().last?.error != nil }

        #expect(failed)
        #expect(collector.transactions().count == 1)
        #expect(collector.transactions().first?.responseStart == nil)
    }

    @Test(
        arguments: [
            ("http/1.1", Internals.TransactionMetrics.NegotiatedProtocol.http1_1),
            ("http/1.0", .http1_1),
            ("h2", .http2),
            ("h3", .other("h3")),
            ("spdy/3.1", .other("spdy/3.1")),
        ]
    )
    func negotiatedProtocol_fromTheALPNName(
        _ name: String,
        _ expected: Internals.TransactionMetrics.NegotiatedProtocol
    ) {
        #expect(Internals.TransactionMetrics.NegotiatedProtocol(name) == expected)
    }

    @Test(
        arguments: [
            (UInt16(0x0301), Internals.TransactionMetrics.TLSVersion.tls10),
            (0x0302, .tls11),
            (0x0303, .tls12),
            (0x0304, .tls13),
        ]
    )
    func tlsVersion_fromTheIANAValue(
        _ value: UInt16,
        _ expected: Internals.TransactionMetrics.TLSVersion
    ) {
        #expect(Internals.TransactionMetrics.TLSVersion(rawValue: value) == expected)
    }

    @Test
    func tlsVersion_whenTheValueHasNoEquivalent_isNil() {
        // DTLS 1.2 and an unassigned value.
        #expect(Internals.TransactionMetrics.TLSVersion(rawValue: 0xFEFD) == nil)
        #expect(Internals.TransactionMetrics.TLSVersion(rawValue: 0) == nil)
    }

    @Test
    func sessionTask_whenCallerGaveADelegate_stillForwardsTheMetricsToIt() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "metrics"), at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)
        let delegate = MetricsForwardingDelegate()

        // When
        let sessionTask = try await client.execute(
            request: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData),
            readingMode: .length(1_024),
            uploadingBytes: .zero,
            decompression: .disabled,
            cache: nil,
            logger: nil,
            delegate: delegate
        )

        try await drain(sessionTask)

        // Then: `URLSession` allows one delegate per task, and the client's own stands between it and the caller's.
        try await eventually { delegate.collectedCount > 0 }
        #expect(delegate.collectedCount == 1)
    }

    // MARK: - Private methods

    /// Ignores `URLSession`'s own cache: a repeated request would otherwise be answered from it,
    /// which is a transaction with no connection at all (see
    /// `sessionTask_whenAnsweredFromURLSessionCache_reportsNoConnection`).
    private func execute(
        _ client: Internals.URLSessionClient,
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    ) async throws -> SessionTask {
        try await client.execute(
            request: URLRequest(url: url, cachePolicy: cachePolicy),
            readingMode: .length(1_024),
            uploadingBytes: .zero,
            decompression: .disabled,
            cache: nil,
            logger: nil,
            delegate: AcceptAnyServerTrustDelegate()
        )
    }

    private func drain(_ sessionTask: SessionTask) async throws {
        for try await step in sessionTask.response {
            if case .download(let downloadStep) = step {
                for try await _ in downloadStep.bytes {}
            }
        }
    }
}

/// A caller's delegate that trusts the test server and counts the metrics it is handed.
private final class MetricsForwardingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    private let lock = Lock()
    private var _collectedCount = 0

    var collectedCount: Int {
        lock.withLock { _collectedCount }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        lock.withLock { _collectedCount += 1 }
    }
}

/// Test-only stand-in for the real client's own TLS challenge handling. See the identical
/// delegate in the other `Internals.URLSessionClient` test files for why this exists at all:
/// `LocalServer` is always TLS-terminated with a throwaway self-signed certificate.
private final class AcceptAnyServerTrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

#endif
