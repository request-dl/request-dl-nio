//
// See LICENSE for this package's licensing information.
//

// What `Internals.Client` reports in `SessionTask.metrics`: the transactions AsyncHTTPClient
// delivers through `didCollectMetrics(task:_:)`, converted by
// `Internals.TransactionMetrics.init(_:)`. The NIO counterpart to
// `InternalsURLSessionClientMetricsTests`.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOSSL
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
import struct Foundation.UUID
#endif

@testable import RequestDLInternals
@testable import RequestDLTestSupport

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsClientMetricsTests {

    private func makeSession(
        collectDNSMetrics: Bool = false,
        redirectConfiguration: Internals.RedirectConfiguration? = nil
    ) -> Internals.Session {
        var configuration = Internals.Session.Configuration()
        configuration.redirectConfiguration = redirectConfiguration
        var secureConnection = Internals.SecureConnection()

        secureConnection.certificateVerification = .some(.none)
        configuration.secureConnection = secureConnection
        configuration.timeout.connect = 60_000_000_000
        configuration.collectDNSMetrics = collectDNSMetrics

        return Internals.Session(
            provider: .identified("com.requestdl.tests.client-metrics-\(UUID())", numberOfThreads: 1),
            configuration: configuration
        )
    }

    @Test
    func whenResponseDrained_reportsTheTransactionAsyncHTTPClientMeasured() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "metrics"), at: uri)
        defer { localServer.cleanup(at: uri) }

        let session = makeSession()

        // When
        let task = try await execute(session: session, localServer: localServer, uri: uri)
        let collector = try #require(task.metrics)

        try await drain(task)

        // Then: delivered before the body ended, so no waiting is needed.
        let transactions = collector.transactions()
        #expect(transactions.count == 1)

        let transaction = try #require(transactions.first)
        let fetchStart = try #require(transaction.fetchStart)
        let requestStart = try #require(transaction.requestStart)
        let requestEnd = try #require(transaction.requestEnd)
        let responseStart = try #require(transaction.responseStart)
        let responseEnd = try #require(transaction.responseEnd)

        #expect(fetchStart <= requestStart)
        #expect(requestStart <= requestEnd)
        #expect(requestEnd <= responseStart)
        #expect(responseStart <= responseEnd)

        #expect(transaction.error == nil)
        #expect((transaction.responseBodyBytesReceived ?? 0) > 0)

        let connection = try #require(transaction.connection)
        #expect(connection.isReused == false)
        #expect(connection.negotiatedProtocol != nil)
        #expect(connection.tlsVersion != nil)

        // A fresh connection went through the phases that establish one, except DNS, which
        // AsyncHTTPClient only reports on request (`collectDNSMetrics`).
        let connect = try #require(connection.connect)
        let secureConnection = try #require(connection.secureConnection)
        #expect(connect.start <= connect.end)
        #expect(secureConnection.start <= secureConnection.end)

        #if !canImport(Network)
        #expect(connection.domainLookup == nil)
        #endif
    }

    @Test
    func whenSecondRequestSharesTheClient_reportsTheConnectionAsReused() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "metrics"), at: uri)
        defer { localServer.cleanup(at: uri) }

        let session = makeSession()
        let client = try await session.client()

        // When
        let first = try await execute(session: session, client: client, localServer: localServer, uri: uri)
        try await drain(first)

        let second = try await execute(session: session, client: client, localServer: localServer, uri: uri)
        let collector = try #require(second.metrics)
        try await drain(second)

        // Then
        let connection = try #require(collector.transactions().first?.connection)
        #expect(connection.isReused == true)
        #expect(connection.domainLookup == nil)
        #expect(connection.connect == nil)
        #expect(connection.secureConnection == nil)
    }

    @Test
    func whenRedirectFollowed_reportsOneTransactionPerHop() async throws {
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

        let session = makeSession(redirectConfiguration: .follow(max: 5, allowCycles: false))

        // When
        let task = try await execute(session: session, localServer: localServer, uri: origin)
        let collector = try #require(task.metrics)
        try await drain(task)

        // Then: AsyncHTTPClient delivers each hop before it starts the next, so by the end of the
        // body all of them are in.
        let transactions = collector.transactions()
        #expect(transactions.map(\.url?.path) == [origin, destination])
        #expect(transactions.first?.connection?.isReused == false)
        #expect(transactions.last?.connection?.isReused == true)
    }

    // MARK: - Revalidation

    /// The buffered request that is not the caller's own (the conditional one that asks whether a
    /// cached response still holds) records what it measured, marked as a revalidation, and still
    /// hands the accumulated response back.
    @Test
    func revalidation_whenTheRequestFollowsARedirect_recordsEveryHopAsARevalidation() async throws {
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

        let session = makeSession(redirectConfiguration: .follow(max: 5, allowCycles: false))
        let client = try await session.client()
        let collector = Internals.RequestMetricsCollector()

        // When
        let response = try await client.execute(
            request: try HTTPClient.Request(url: "https://\(localServer.baseURL)\(origin)"),
            logger: nil,
            metrics: collector,
            source: .revalidation
        ).response()

        // Then
        #expect(response.status.code == 200)

        let transactions = collector.transactions()
        #expect(transactions.map(\.source) == [.revalidation, .revalidation])
        #expect(transactions.map(\.url?.path) == [origin, destination])
    }

    @Test
    func revalidation_whenTheRequestFails_recordsTheTransactionWithItsError() async throws {
        // Given: a port that refuses connections.
        let refused = try RefusedPort()
        defer { refused.release() }
        let port = refused.port

        let session = makeSession()
        let client = try await session.client()
        let collector = Internals.RequestMetricsCollector()

        // When
        await #expect(throws: (any Error).self) {
            _ = try await client.execute(
                request: try HTTPClient.Request(url: "http://127.0.0.1:\(port)/resource"),
                logger: nil,
                metrics: collector,
                source: .revalidation
            ).response()
        }

        // Then
        let transactions = collector.transactions()
        #expect(transactions.map(\.source) == [.revalidation])
        #expect(transactions.first?.error != nil)
    }

    @Test
    func whenConnectionRefused_recordsTheErrorOnTheTransaction() async throws {
        // Given: a port that refuses connections.
        let refused = try RefusedPort()
        defer { refused.release() }
        let port = refused.port

        let session = makeSession()
        let client = try await session.client()
        let urlString = "http://127.0.0.1:\(port)/resource"

        // When
        let task = try await session.execute(
            client: client,
            request: try HTTPClient.Request(url: urlString),
            url: urlString,
            readingMode: .length(1_024),
            uploadingBytes: .zero,
            decompression: .disabled,
            cache: nil,
            logger: nil
        )

        let collector = try #require(task.metrics)
        var failed = false

        do {
            try await drain(task)
        } catch {
            failed = true
        }

        // Then
        try await eventually { collector.transactions().last?.error != nil }

        #expect(failed)
        #expect(collector.transactions().count == 1)
        #expect(collector.transactions().first?.responseStart == nil)
    }

    #if !canImport(Network)
    @Test
    func whenCollectingDNSMetrics_reportsTheLookup() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "metrics"), at: uri)
        defer { localServer.cleanup(at: uri) }

        let session = makeSession(collectDNSMetrics: true)

        // When
        let task = try await execute(session: session, localServer: localServer, uri: uri)
        let collector = try #require(task.metrics)
        try await drain(task)

        // Then
        let connection = try #require(collector.transactions().first?.connection)
        let lookup = try #require(connection.domainLookup)
        let connect = try #require(connection.connect)

        #expect(lookup.start <= lookup.end)
        #expect(lookup.end <= connect.start)
    }
    #endif

    // MARK: - Conversion

    @Test
    func conversion_whenHTTP2OverEveryTLSVersion_isCarriedOver() throws {
        let versions: [(TLSVersion, Internals.TransactionMetrics.TLSVersion)] = [
            (.tlsv1, .tls10),
            (.tlsv11, .tls11),
            (.tlsv12, .tls12),
            (.tlsv13, .tls13),
        ]

        for (input, expected) in versions {
            // Given
            let transaction = HTTPClientTransactionMetrics(
                url: try #require(URL(string: "https://example.com")),
                fetchStartDate: Date(timeIntervalSince1970: 100),
                connection: .init(
                    id: 1,
                    negotiatedProtocol: .http2,
                    isReused: false,
                    tlsVersion: input,
                    tlsCipherSuite: 0x1301
                )
            )

            // When
            let converted = Internals.TransactionMetrics(transaction)

            // Then
            #expect(converted.connection?.negotiatedProtocol == .http2)
            #expect(converted.connection?.tlsVersion == expected)
            #expect(converted.connection?.tlsCipherSuite == 0x1301)
        }
    }

    @Test
    func conversion_whenHTTP1_isCarriedOver() throws {
        // Given
        let transaction = HTTPClientTransactionMetrics(
            url: try #require(URL(string: "http://example.com")),
            fetchStartDate: Date(timeIntervalSince1970: 100),
            connection: .init(id: 1, negotiatedProtocol: .http1_1, isReused: true)
        )

        // When
        let converted = Internals.TransactionMetrics(transaction)

        // Then
        #expect(converted.connection?.negotiatedProtocol == .http1_1)
        #expect(converted.connection?.isReused == true)
        #expect(converted.connection?.tlsVersion == nil)
    }

    @Test
    func conversion_whenAddressesAreIPAndUnixSockets_keepsTheHostAndPort() throws {
        // Given
        let transaction = HTTPClientTransactionMetrics(
            url: try #require(URL(string: "http://example.com")),
            fetchStartDate: Date(timeIntervalSince1970: 100),
            connection: .init(
                id: 1,
                negotiatedProtocol: .http1_1,
                isReused: false,
                localAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 1234),
                remoteAddress: try SocketAddress(unixDomainSocketPath: "/tmp/requestdl.sock")
            )
        )

        // When
        let connection = try #require(Internals.TransactionMetrics(transaction).connection)

        // Then
        #expect(connection.localAddress == "127.0.0.1")
        #expect(connection.localPort == 1234)
        #expect(connection.remoteAddress == "/tmp/requestdl.sock")
        #expect(connection.remotePort == nil)
    }

    @Test
    func conversion_whenTheTransactionNeverGotAConnection_hasNone() throws {
        // Given
        let transaction = HTTPClientTransactionMetrics(
            url: try #require(URL(string: "http://example.com")),
            fetchStartDate: Date(timeIntervalSince1970: 100),
            error: HTTPClientError.cancelled
        )

        // When
        let converted = Internals.TransactionMetrics(transaction)

        // Then
        #expect(converted.connection == nil)
        #expect(converted.error as? HTTPClientError == .cancelled)
    }

    // MARK: - Private methods

    private func execute(
        session: Internals.Session,
        client: Internals.Client? = nil,
        localServer: LocalServer,
        uri: String
    ) async throws -> SessionTask {
        let client = if let client { client } else { try await session.client() }
        let urlString = "https://\(localServer.baseURL)\(uri)"

        return try await session.execute(
            client: client,
            request: try HTTPClient.Request(url: urlString),
            url: urlString,
            readingMode: .length(1_024),
            uploadingBytes: .zero,
            decompression: .disabled,
            cache: nil,
            logger: nil
        )
    }

    private func drain(_ task: SessionTask) async throws {
        for try await step in task.response {
            if case .download(let downloadStep) = step {
                for try await _ in downloadStep.bytes {}
            }
        }
    }
}

#endif
