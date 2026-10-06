//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import struct Foundation.URL
#endif

extension Internals {

    /// What one request/response exchange on the wire measured, in a form both transports can fill.
    ///
    /// URLSession reports its `URLSessionTaskTransactionMetrics` and AsyncHTTPClient its
    /// `HTTPClientTransactionMetrics`. Each transport converts its own into this, so everything above
    /// the transport deals with a single type and needs no platform branch.
    ///
    /// Every phase is `nil` when it was never reached, or when the transport cannot observe it.
    package struct TransactionMetrics: Sendable {

        /// A start and an end of one phase.
        package struct Interval: Sendable, Hashable {
            package let start: Date
            package let end: Date

            package init(start: Date, end: Date) {
                self.start = start
                self.end = end
            }

            /// `nil` unless the phase both started and ended, since a half-measured phase has no duration.
            package init?(start: Date?, end: Date?) {
                guard let start, let end else {
                    return nil
                }

                self.init(start: start, end: end)
            }
        }

        /// Where the response of a transaction came from.
        package enum Source: Sendable, Hashable {

            /// An exchange on the wire that carried the request itself.
            case network

            /// A response served from the cache, with nothing exchanged on the wire.
            case cache

            /// The conditional request sent to ask whether a cached response is still valid. It is a
            /// request of its own, not the one the caller made.
            case revalidation
        }

        /// The application protocol negotiated for the connection.
        package enum NegotiatedProtocol: Sendable, Hashable {
            case http1_1
            case http2
            case other(String)
        }

        /// The TLS version negotiated for the connection.
        package enum TLSVersion: Sendable, Hashable {
            case tls10
            case tls11
            case tls12
            case tls13
        }

        /// The connection the exchange ran on.
        package struct Connection: Sendable {
            package var negotiatedProtocol: NegotiatedProtocol?
            package var isReused: Bool
            package var localAddress: String?
            package var localPort: Int?
            package var remoteAddress: String?
            package var remotePort: Int?
            package var isProxyConnection: Bool
            package var tlsVersion: TLSVersion?
            package var tlsCipherSuite: UInt16?
            package var domainLookup: Interval?
            package var connect: Interval?
            package var secureConnection: Interval?

            package init(
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

        package var source: Source
        package var url: URL?
        package var fetchStart: Date?
        package var queued: Date?
        package var requestStart: Date?
        package var requestEnd: Date?
        package var responseStart: Date?
        package var responseEnd: Date?

        package var requestHeaderBytesSent: Int?
        package var requestBodyBytesSent: Int?
        package var requestBodyBytesBeforeEncoding: Int?
        package var responseHeaderBytesReceived: Int?
        package var responseBodyBytesReceived: Int?
        package var responseBodyBytesAfterDecoding: Int?

        package var connection: Connection?
        package var error: (any Error)?

        package init(
            source: Source = .network,
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
            self.source = source
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
    }
}
