//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import struct Foundation.UUID
import struct Foundation.Data
#endif

extension ResponseHead {

    fileprivate static let stub = ResponseHead(
        url: nil,
        status: .init(code: 200, reason: "OK"),
        version: .init(minor: 1, major: 1),
        headers: HTTPHeaders(),
        isKeepAlive: false
    )
}

/// `TaskResult.metrics` end to end, through the public `DataTask`/`DownloadTask` API, under each
/// executor: the collector the transport fills has to survive `RawTask`, `AsyncResponse.collect()`
/// and the modifiers that rebuild the result around a new payload.
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct TaskResultMetricsTests {

    // MARK: - Without a transport

    @Test
    func taskResult_whenBuiltByPublicInit_hasNoMetrics() {
        // Given
        let result = TaskResult(head: .stub, payload: Data())

        // Then
        #expect(result.metrics == nil)
    }

    @Test
    func taskResult_whenCollectorHasNoTransactionYet_hasNoMetrics() {
        // Given
        let result = TaskResult(
            head: .stub,
            payload: Data(),
            metrics: Internals.RequestMetricsCollector()
        )

        // Then: nothing measured is not the same as measured nothing.
        #expect(result.metrics == nil)
    }

    @Test
    func taskResult_whenTransformingPayload_carriesTheMetricsAlong() throws {
        // Given
        let collector = Internals.RequestMetricsCollector()
        let result = TaskResult(head: .stub, payload: Data(), metrics: collector)

        // When
        let transformed = result.withPayload("payload")
        collector.append(Internals.TransactionMetrics())

        // Then: read when asked for, so a transaction that ended after the transformation shows.
        #expect(transformed.payload == "payload")
        #expect(transformed.metrics?.transactions.count == 1)
    }

    @Test
    func requestMetrics_fetchInterval_goesFromTheFirstFetchToTheLastResponseEnd() throws {
        // Given
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 103)

        let metrics = RequestMetrics(
            transactions: [
                .init(fetchStart: start, responseEnd: Date(timeIntervalSince1970: 101)),
                .init(fetchStart: Date(timeIntervalSince1970: 101), responseEnd: end),
            ]
        )

        // Then
        let interval = try #require(metrics.fetchInterval)
        #expect(interval.start == start)
        #expect(interval.end == end)
        #expect(interval.duration == 3)
    }

    @Test
    func requestMetrics_fetchInterval_whenLastResponseNeverEnded_isNil() {
        // Given
        let metrics = RequestMetrics(
            transactions: [.init(fetchStart: Date(timeIntervalSince1970: 100))]
        )

        // Then
        #expect(metrics.fetchInterval == nil)
    }

    @Test
    func transaction_whenEveryFieldMatches_isEqual() {
        // Given
        let date = Date(timeIntervalSince1970: 100)
        let connection = RequestMetrics.Connection(
            negotiatedProtocol: .http2,
            isReused: true,
            tlsVersion: .tls13,
            connect: .init(start: date, end: date.addingTimeInterval(1))
        )

        // Then
        #expect(
            RequestMetrics.Transaction(fetchStart: date, connection: connection)
                == RequestMetrics.Transaction(fetchStart: date, connection: connection)
        )
    }

    @Test
    func transaction_whenAnyFieldDiffers_isNotEqual() {
        // Given
        let date = Date(timeIntervalSince1970: 100)
        let base = RequestMetrics.Transaction(fetchStart: date, responseBodyBytesReceived: 10)

        // Then
        #expect(base != RequestMetrics.Transaction(fetchStart: date, responseBodyBytesReceived: 11))
        #expect(
            base != RequestMetrics.Transaction(fetchStart: date.addingTimeInterval(1), responseBodyBytesReceived: 10)
        )
        #expect(
            base
                != RequestMetrics.Transaction(
                    fetchStart: date,
                    responseBodyBytesReceived: 10,
                    connection: .init(isReused: false)
                )
        )
    }

    @Test
    func transaction_whenComparingErrors_usesTypeAndDescription() {
        // Given
        struct FirstError: Error { let reason: String }
        struct SecondError: Error { let reason: String }

        let date = Date(timeIntervalSince1970: 100)

        func transaction(error: (any Error)?) -> RequestMetrics.Transaction {
            .init(fetchStart: date, error: error)
        }

        // Then: the same type describing itself the same way is the same error.
        #expect(transaction(error: FirstError(reason: "a")) == transaction(error: FirstError(reason: "a")))
        #expect(transaction(error: nil) == transaction(error: nil))

        // Different description, different type, or no error at all, is not.
        #expect(transaction(error: FirstError(reason: "a")) != transaction(error: FirstError(reason: "b")))
        #expect(transaction(error: FirstError(reason: "a")) != transaction(error: SecondError(reason: "a")))
        #expect(transaction(error: FirstError(reason: "a")) != transaction(error: nil))
        #expect(transaction(error: nil) != transaction(error: FirstError(reason: "a")))
    }

    @Test
    func requestMetrics_whenTransactionsMatch_isEqual() {
        // Given
        let date = Date(timeIntervalSince1970: 100)
        let transactions = [RequestMetrics.Transaction(fetchStart: date)]

        // Then
        #expect(RequestMetrics(transactions: transactions) == RequestMetrics(transactions: transactions))
        #expect(RequestMetrics(transactions: transactions) != RequestMetrics(transactions: []))
    }

    @Test
    func mockedTask_whenCollected_hasNoMetrics() async throws {
        // When: nothing goes over the wire, so there is nothing to have measured.
        let result = try await MockedTask {
            BaseURL("localhost")
            Payload(["key": true])
        }
        .collectData()
        .result()

        // Then
        #expect(result.metrics == nil)
    }

    // MARK: - Over the wire

    @Test
    func dataTask_whenCompleted_reportsMetricsOfTheTransaction() async throws {
        // Given
        let (localServer, uri) = try await makeServer()
        defer { localServer.cleanup(at: uri) }

        // When
        let result = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .result()

        // Then
        try expectCompleteTransaction(result.metrics)
    }

    #if canImport(Darwin)
    @Test
    func dataTask_whenPinnedToURLSession_reportsMetricsOfTheTransaction() async throws {
        // Given
        let (localServer, uri) = try await makeServer()
        defer { localServer.cleanup(at: uri) }

        // When
        let result = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.metrics.urlsession.\(UUID())")
                .requiredExecutor(.urlSession)

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .result()

        // Then
        try expectCompleteTransaction(result.metrics)
    }
    #endif

    #if canImport(NIOCore)
    @Test
    func dataTask_whenPinnedToNIO_reportsMetricsOfTheTransaction() async throws {
        // Given
        let (localServer, uri) = try await makeServer()
        defer { localServer.cleanup(at: uri) }

        // When
        let result = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.metrics.nio.\(UUID())")
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .result()

        // Then
        try expectCompleteTransaction(result.metrics)
    }
    #endif

    @Test
    func downloadTask_whenBodyConsumed_reportsTheResponseEnd() async throws {
        // Given
        let (localServer, uri) = try await makeServer()
        defer { localServer.cleanup(at: uri) }

        // When
        let result = try await DownloadTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .result()

        for try await _ in result.payload {}

        // Then: only now has the last transaction ended for sure.
        try expectCompleteTransaction(result.metrics)
    }

    // MARK: - Private methods

    private func makeServer() async throws -> (LocalServer, String) {
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello World"), at: uri)

        return (localServer, uri)
    }

    private func expectCompleteTransaction(_ metrics: RequestMetrics?) throws {
        let metrics = try #require(metrics)
        #expect(metrics.transactions.count == 1)

        let transaction = try #require(metrics.transactions.first)
        let fetchStart = try #require(transaction.fetchStart)
        let requestStart = try #require(transaction.requestStart)
        let responseStart = try #require(transaction.responseStart)
        let responseEnd = try #require(transaction.responseEnd)

        #expect(fetchStart <= requestStart)
        #expect(requestStart <= responseStart)
        #expect(responseStart <= responseEnd)
        #expect(transaction.connection != nil)
        #expect(metrics.fetchInterval != nil)
    }
}
