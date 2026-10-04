//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOSSL

extension Internals.TransactionMetrics {

    /// Converts what AsyncHTTPClient measured for one transaction.
    ///
    /// Everything it reports is carried over. A phase that was never reached, or that this
    /// transport cannot observe (see `HTTPClient.Configuration.collectDNSMetrics`), is `nil` there
    /// already, and stays `nil` here.
    package init(_ transaction: HTTPClientTransactionMetrics) {
        self.init(
            url: transaction.url,
            fetchStart: transaction.fetchStartDate,
            queued: transaction.queuedDate,
            requestStart: transaction.requestStartDate,
            requestEnd: transaction.requestEndDate,
            responseStart: transaction.responseStartDate,
            responseEnd: transaction.responseEndDate,
            requestHeaderBytesSent: transaction.requestHeaderBytesSent,
            requestBodyBytesSent: transaction.requestBodyBytesSent,
            requestBodyBytesBeforeEncoding: transaction.requestBodyBytesBeforeEncoding,
            responseHeaderBytesReceived: transaction.responseHeaderBytesReceived,
            responseBodyBytesReceived: transaction.responseBodyBytesReceived,
            responseBodyBytesAfterDecoding: transaction.responseBodyBytesAfterDecoding,
            connection: transaction.connection.map(Connection.init),
            error: transaction.error
        )
    }
}

extension Internals.TransactionMetrics.Connection {

    fileprivate init(_ connection: HTTPClientTransactionMetrics.Connection) {
        self.init(
            negotiatedProtocol: .init(connection.negotiatedProtocol),
            isReused: connection.isReused,
            localAddress: connection.localAddress?.host,
            localPort: connection.localAddress?.port,
            remoteAddress: connection.remoteAddress?.host,
            remotePort: connection.remoteAddress?.port,
            isProxyConnection: connection.isProxyConnection,
            tlsVersion: connection.tlsVersion.flatMap(Internals.TransactionMetrics.TLSVersion.init),
            tlsCipherSuite: connection.tlsCipherSuite,
            domainLookup: Internals.TransactionMetrics.Interval(
                start: connection.domainLookupStartDate,
                end: connection.domainLookupEndDate
            ),
            connect: Internals.TransactionMetrics.Interval(
                start: connection.connectStartDate,
                end: connection.connectEndDate
            ),
            secureConnection: Internals.TransactionMetrics.Interval(
                start: connection.secureConnectionStartDate,
                end: connection.secureConnectionEndDate
            )
        )
    }
}

extension Internals.TransactionMetrics.NegotiatedProtocol {

    fileprivate init(_ negotiatedProtocol: HTTPClientTransactionMetrics.Connection.NegotiatedProtocol) {
        switch negotiatedProtocol {
        case .http1_1:
            self = .http1_1
        case .http2:
            self = .http2
        }
    }
}

extension Internals.TransactionMetrics.TLSVersion {

    fileprivate init?(_ version: TLSVersion) {
        switch version {
        case .tlsv1:
            self = .tls10
        case .tlsv11:
            self = .tls11
        case .tlsv12:
            self = .tls12
        case .tlsv13:
            self = .tls13
        }
    }
}

extension SocketAddress {

    /// The address without its port: the IP for a network socket, the path for a unix one.
    fileprivate var host: String? {
        switch self {
        case .v4, .v6:
            ipAddress
        case .unixDomainSocket:
            pathname
        }
    }
}

#endif
