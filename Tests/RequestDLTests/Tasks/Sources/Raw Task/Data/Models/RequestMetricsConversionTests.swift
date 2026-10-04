//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import struct Foundation.URL
#endif

/// The conversion from what an executor recorded (`Internals.TransactionMetrics`) to the public
/// `RequestMetrics`, for every case of every enum it carries.
struct RequestMetricsConversionTests {

    @Test(
        arguments: [
            (Internals.TransactionMetrics.NegotiatedProtocol.http1_1, RequestMetrics.NegotiatedProtocol.http1_1),
            (.http2, .http2),
            (.other("h3"), .other("h3")),
        ]
    )
    func negotiatedProtocol_isCarriedOver(
        _ input: Internals.TransactionMetrics.NegotiatedProtocol,
        _ expected: RequestMetrics.NegotiatedProtocol
    ) {
        // When
        let metrics = RequestMetrics([
            .init(connection: .init(negotiatedProtocol: input, isReused: false))
        ])

        // Then
        #expect(metrics.transactions.first?.connection?.negotiatedProtocol == expected)
    }

    @Test(
        arguments: [
            (Internals.TransactionMetrics.TLSVersion.tls10, RequestMetrics.TLSVersion.tls10),
            (.tls11, .tls11),
            (.tls12, .tls12),
            (.tls13, .tls13),
        ]
    )
    func tlsVersion_isCarriedOver(
        _ input: Internals.TransactionMetrics.TLSVersion,
        _ expected: RequestMetrics.TLSVersion
    ) {
        // When
        let metrics = RequestMetrics([
            .init(connection: .init(isReused: false, tlsVersion: input))
        ])

        // Then
        #expect(metrics.transactions.first?.connection?.tlsVersion == expected)
    }

    @Test
    func transaction_carriesEveryFieldOver() throws {
        // Given
        let url = try #require(URL(string: "https://example.com/path"))
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 102)
        let error = CancellationError()

        let transaction = Internals.TransactionMetrics(
            url: url,
            fetchStart: start,
            queued: start,
            requestStart: start,
            requestEnd: end,
            responseStart: start,
            responseEnd: end,
            requestHeaderBytesSent: 1,
            requestBodyBytesSent: 2,
            requestBodyBytesBeforeEncoding: 3,
            responseHeaderBytesReceived: 4,
            responseBodyBytesReceived: 5,
            responseBodyBytesAfterDecoding: 6,
            connection: .init(
                negotiatedProtocol: .http2,
                isReused: true,
                localAddress: "127.0.0.1",
                localPort: 1,
                remoteAddress: "10.0.0.1",
                remotePort: 443,
                isProxyConnection: true,
                tlsVersion: .tls13,
                tlsCipherSuite: 0x1301,
                domainLookup: .init(start: start, end: end),
                connect: .init(start: start, end: end),
                secureConnection: .init(start: start, end: end)
            ),
            error: error
        )

        // When
        let result = try #require(RequestMetrics([transaction]).transactions.first)

        // Then
        #expect(result.url == url)
        #expect(result.fetchStart == start)
        #expect(result.queued == start)
        #expect(result.requestStart == start)
        #expect(result.requestEnd == end)
        #expect(result.responseStart == start)
        #expect(result.responseEnd == end)
        #expect(result.requestHeaderBytesSent == 1)
        #expect(result.requestBodyBytesSent == 2)
        #expect(result.requestBodyBytesBeforeEncoding == 3)
        #expect(result.responseHeaderBytesReceived == 4)
        #expect(result.responseBodyBytesReceived == 5)
        #expect(result.responseBodyBytesAfterDecoding == 6)
        #expect(result.error is CancellationError)

        let connection = try #require(result.connection)
        #expect(connection.isReused)
        #expect(connection.localAddress == "127.0.0.1")
        #expect(connection.localPort == 1)
        #expect(connection.remoteAddress == "10.0.0.1")
        #expect(connection.remotePort == 443)
        #expect(connection.isProxyConnection)
        #expect(connection.tlsCipherSuite == 0x1301)
        #expect(connection.domainLookup == .init(start: start, end: end))
        #expect(connection.connect?.duration == 2)
        #expect(connection.secureConnection == .init(start: start, end: end))
    }

    @Test
    func transaction_whenNothingWasMeasured_keepsEverythingNil() throws {
        // When
        let result = try #require(RequestMetrics([.init()]).transactions.first)

        // Then
        #expect(result.url == nil)
        #expect(result.fetchStart == nil)
        #expect(result.connection == nil)
        #expect(result.error == nil)
    }
}
