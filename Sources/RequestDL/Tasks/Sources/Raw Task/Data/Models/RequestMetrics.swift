//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import struct Foundation.URL
#endif

/// What a request measured on the wire, one ``Transaction`` per exchange it went through.
///
/// A request that follows a redirect runs one transaction for each hop, in order, and one that is
/// retried on a fresh connection runs one for each attempt. The same values come out of both
/// executors, `URLSession` and AsyncHTTPClient, with a few phases only one of them can observe. Each of
/// those is documented where it is declared, and is `nil` when it cannot be observed.
///
/// Read it from ``TaskResult/metrics``.
public struct RequestMetrics: Sendable, Equatable {

    /// A start and an end of one phase.
    public struct Interval: Sendable, Hashable {

        /// When the phase started.
        public let start: Date

        /// When the phase ended.
        public let end: Date

        /// How long the phase took, in seconds.
        public var duration: Double {
            end.timeIntervalSince(start)
        }

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    /// The application protocol negotiated for a connection.
    public enum NegotiatedProtocol: Sendable, Hashable {

        /// HTTP/1.0 or HTTP/1.1.
        case http1_1

        /// HTTP/2.
        case http2

        /// Any other protocol, by the name the transport reported, such as `h3`.
        case other(String)
    }

    /// The TLS version negotiated for a connection.
    public enum TLSVersion: Sendable, Hashable {
        case tls10
        case tls11
        case tls12
        case tls13
    }

    /// The connection a transaction ran on.
    public struct Connection: Sendable, Equatable {

        /// The protocol negotiated for the connection.
        public let negotiatedProtocol: NegotiatedProtocol?

        /// Whether the connection had already carried another transaction.
        ///
        /// When it had, the phases that establish a connection (``domainLookup``, ``connect`` and
        /// ``secureConnection``) are `nil`, since this transaction did not go through them.
        public let isReused: Bool

        /// The local address of the connection, without its port.
        public let localAddress: String?

        /// The local port of the connection.
        public let localPort: Int?

        /// The remote address of the connection, without its port.
        public let remoteAddress: String?

        /// The remote port of the connection.
        public let remotePort: Int?

        /// Whether the connection goes through a proxy.
        public let isProxyConnection: Bool

        /// The TLS version negotiated, or `nil` when the connection does not use TLS.
        public let tlsVersion: TLSVersion?

        /// The negotiated TLS cipher suite, by its number in the IANA registry (`0x1301` for
        /// `TLS_AES_128_GCM_SHA256`).
        ///
        /// AsyncHTTPClient only knows it for connections made with the Network framework, and it is
        /// `nil` everywhere else.
        public let tlsCipherSuite: UInt16?

        /// The lookup of the host name.
        ///
        /// AsyncHTTPClient only reports it on a POSIX platform when the session sets
        /// ``Session/collectDNSMetrics()``. On the Network framework, it is always reported.
        public let domainLookup: Interval?

        /// The connection being made. With a proxy, it includes setting up the tunnel.
        public let connect: Interval?

        /// The TLS handshake.
        public let secureConnection: Interval?

        public init(
            negotiatedProtocol: NegotiatedProtocol? = nil,
            isReused: Bool,
            localAddress: String? = nil,
            localPort: Int? = nil,
            remoteAddress: String? = nil,
            remotePort: Int? = nil,
            isProxyConnection: Bool = false,
            tlsVersion: TLSVersion? = nil,
            tlsCipherSuite: UInt16? = nil,
            domainLookup: Interval? = nil,
            connect: Interval? = nil,
            secureConnection: Interval? = nil
        ) {
            self.negotiatedProtocol = negotiatedProtocol
            self.isReused = isReused
            self.localAddress = localAddress
            self.localPort = localPort
            self.remoteAddress = remoteAddress
            self.remotePort = remotePort
            self.isProxyConnection = isProxyConnection
            self.tlsVersion = tlsVersion
            self.tlsCipherSuite = tlsCipherSuite
            self.domainLookup = domainLookup
            self.connect = connect
            self.secureConnection = secureConnection
        }
    }

    /// One request/response exchange on the wire.
    ///
    /// Every date and count is `nil` when it was never reached, or when the executor cannot observe it.
    ///
    /// Two transactions are equal when every field is, and ``error`` is compared by the type of the error and its
    /// description (`String(reflecting:)`), since `Error` itself is not `Equatable`. Two different errors that
    /// share a type and a description therefore compare equal.
    public struct Transaction: Sendable, Equatable {

        /// The URL this transaction was sent to.
        public let url: URL?

        /// When the executor started working on the request.
        public let fetchStart: Date?

        /// When the request started to wait for a connection to become available.
        ///
        /// Only AsyncHTTPClient reports it, and only when a connection was not available right away.
        public let queued: Date?

        /// When a connection was assigned and the request head started to be written.
        public let requestStart: Date?

        /// When the complete request, including its body, was handed to the connection.
        public let requestEnd: Date?

        /// When the response head was received.
        public let responseStart: Date?

        /// When the complete response was received from the connection.
        ///
        /// This is when the last byte arrived, not when it was consumed.
        public let responseEnd: Date?

        /// The bytes of the request head that were sent. `nil` for HTTP/2, which compresses them.
        public let requestHeaderBytesSent: Int?

        /// The bytes of the request body that were sent, with what the transfer encoding adds.
        public let requestBodyBytesSent: Int?

        /// The bytes of the request body as they were given, before the transfer encoding.
        public let requestBodyBytesBeforeEncoding: Int?

        /// The bytes of the response head that were received. `nil` for HTTP/2.
        public let responseHeaderBytesReceived: Int?

        /// The bytes of the response body that were received, before they were decompressed.
        public let responseBodyBytesReceived: Int?

        /// The bytes of the response body as they were delivered, after they were decompressed.
        public let responseBodyBytesAfterDecoding: Int?

        /// The connection the transaction ran on, or `nil` if it never got one, or if it was answered
        /// from a cache.
        public let connection: Connection?

        /// The error that ended the transaction, if any.
        ///
        /// AsyncHTTPClient reports it for the transaction itself. `URLSession` only does for the task as a whole,
        /// so there it is the error of the exchange that failed, recorded on the transaction that exchange ran
        /// as: a transaction that went through (a redirect hop, or an attempt a download then continued from)
        /// has none.
        ///
        /// A request that fails as a whole throws, so there is no ``TaskResult`` to read this from. It is
        /// visible when the failure came after the response head and the body is read from a
        /// ``TaskResult`` of `AsyncBytes`, or when an earlier attempt of a download failed and a continuation
        /// finished it.
        public let error: (any Error)?

        public init(
            url: URL? = nil,
            fetchStart: Date? = nil,
            queued: Date? = nil,
            requestStart: Date? = nil,
            requestEnd: Date? = nil,
            responseStart: Date? = nil,
            responseEnd: Date? = nil,
            requestHeaderBytesSent: Int? = nil,
            requestBodyBytesSent: Int? = nil,
            requestBodyBytesBeforeEncoding: Int? = nil,
            responseHeaderBytesReceived: Int? = nil,
            responseBodyBytesReceived: Int? = nil,
            responseBodyBytesAfterDecoding: Int? = nil,
            connection: Connection? = nil,
            error: (any Error)? = nil
        ) {
            self.url = url
            self.fetchStart = fetchStart
            self.queued = queued
            self.requestStart = requestStart
            self.requestEnd = requestEnd
            self.responseStart = responseStart
            self.responseEnd = responseEnd
            self.requestHeaderBytesSent = requestHeaderBytesSent
            self.requestBodyBytesSent = requestBodyBytesSent
            self.requestBodyBytesBeforeEncoding = requestBodyBytesBeforeEncoding
            self.responseHeaderBytesReceived = responseHeaderBytesReceived
            self.responseBodyBytesReceived = responseBodyBytesReceived
            self.responseBodyBytesAfterDecoding = responseBodyBytesAfterDecoding
            self.connection = connection
            self.error = error
        }

        // MARK: - Public static methods

        public static func == (lhs: Transaction, rhs: Transaction) -> Bool {
            lhs.url == rhs.url
                && lhs.fetchStart == rhs.fetchStart
                && lhs.queued == rhs.queued
                && lhs.requestStart == rhs.requestStart
                && lhs.requestEnd == rhs.requestEnd
                && lhs.responseStart == rhs.responseStart
                && lhs.responseEnd == rhs.responseEnd
                && lhs.requestHeaderBytesSent == rhs.requestHeaderBytesSent
                && lhs.requestBodyBytesSent == rhs.requestBodyBytesSent
                && lhs.requestBodyBytesBeforeEncoding == rhs.requestBodyBytesBeforeEncoding
                && lhs.responseHeaderBytesReceived == rhs.responseHeaderBytesReceived
                && lhs.responseBodyBytesReceived == rhs.responseBodyBytesReceived
                && lhs.responseBodyBytesAfterDecoding == rhs.responseBodyBytesAfterDecoding
                && lhs.connection == rhs.connection
                && Self.isEqual(lhs.error, rhs.error)
        }

        // MARK: - Private static methods

        /// `Error` is not `Equatable`, so two errors are the same when they are of the same type and describe
        /// themselves the same way.
        private static func isEqual(_ lhs: (any Error)?, _ rhs: (any Error)?) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil):
                true
            case (let lhs?, let rhs?):
                type(of: lhs) == type(of: rhs) && String(reflecting: lhs) == String(reflecting: rhs)
            default:
                false
            }
        }
    }

    // MARK: - Public properties

    /// The transactions the request went through, in the order they ended.
    public let transactions: [Transaction]

    /// From the start of the first transaction to the end of the last one's response, or `nil` when
    /// either is not known.
    ///
    /// It is the time of a fetch that completed. It is `nil` when the last transaction failed or did not
    /// finish, including a body that has not been consumed yet, since there is no end to measure up to.
    /// ``Transaction/error`` says whether it failed.
    public var fetchInterval: Interval? {
        guard
            let start = transactions.first?.fetchStart,
            let end = transactions.last?.responseEnd
        else {
            return nil
        }

        return Interval(start: start, end: end)
    }

    // MARK: - Inits

    public init(transactions: [Transaction]) {
        self.transactions = transactions
    }
}

// MARK: - Internals

extension RequestMetrics {

    init(_ transactions: [Internals.TransactionMetrics]) {
        self.init(transactions: transactions.map(Transaction.init))
    }
}

extension RequestMetrics.Transaction {

    init(_ transaction: Internals.TransactionMetrics) {
        self.init(
            url: transaction.url,
            fetchStart: transaction.fetchStart,
            queued: transaction.queued,
            requestStart: transaction.requestStart,
            requestEnd: transaction.requestEnd,
            responseStart: transaction.responseStart,
            responseEnd: transaction.responseEnd,
            requestHeaderBytesSent: transaction.requestHeaderBytesSent,
            requestBodyBytesSent: transaction.requestBodyBytesSent,
            requestBodyBytesBeforeEncoding: transaction.requestBodyBytesBeforeEncoding,
            responseHeaderBytesReceived: transaction.responseHeaderBytesReceived,
            responseBodyBytesReceived: transaction.responseBodyBytesReceived,
            responseBodyBytesAfterDecoding: transaction.responseBodyBytesAfterDecoding,
            connection: transaction.connection.map(RequestMetrics.Connection.init),
            error: transaction.error
        )
    }
}

extension RequestMetrics.Connection {

    fileprivate init(_ connection: Internals.TransactionMetrics.Connection) {
        self.init(
            negotiatedProtocol: connection.negotiatedProtocol.map(RequestMetrics.NegotiatedProtocol.init),
            isReused: connection.isReused,
            localAddress: connection.localAddress,
            localPort: connection.localPort,
            remoteAddress: connection.remoteAddress,
            remotePort: connection.remotePort,
            isProxyConnection: connection.isProxyConnection,
            tlsVersion: connection.tlsVersion.map(RequestMetrics.TLSVersion.init),
            tlsCipherSuite: connection.tlsCipherSuite,
            domainLookup: connection.domainLookup.map(RequestMetrics.Interval.init),
            connect: connection.connect.map(RequestMetrics.Interval.init),
            secureConnection: connection.secureConnection.map(RequestMetrics.Interval.init)
        )
    }
}

extension RequestMetrics.Interval {

    fileprivate init(_ interval: Internals.TransactionMetrics.Interval) {
        self.init(start: interval.start, end: interval.end)
    }
}

extension RequestMetrics.NegotiatedProtocol {

    fileprivate init(_ negotiatedProtocol: Internals.TransactionMetrics.NegotiatedProtocol) {
        switch negotiatedProtocol {
        case .http1_1:
            self = .http1_1
        case .http2:
            self = .http2
        case .other(let name):
            self = .other(name)
        }
    }
}

extension RequestMetrics.TLSVersion {

    fileprivate init(_ version: Internals.TransactionMetrics.TLSVersion) {
        switch version {
        case .tls10:
            self = .tls10
        case .tls11:
            self = .tls11
        case .tls12:
            self = .tls12
        case .tls13:
            self = .tls13
        }
    }
}
