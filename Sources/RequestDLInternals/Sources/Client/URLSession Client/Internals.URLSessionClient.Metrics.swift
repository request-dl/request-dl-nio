//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.TransactionMetrics {

    /// Converts what `URLSession` measured for one exchange.
    ///
    /// Everything `URLSessionTaskTransactionMetrics` reports is carried over. What it has no
    /// counterpart for stays `nil`: the time a request waited for a connection (`queued`), and the
    /// error of a single transaction, which `URLSession` only reports for the task as a whole.
    ///
    /// An exchange `URLSession` answered from its own cache never touched the network, so it has no
    /// connection to describe.
    package init(_ transaction: URLSessionTaskTransactionMetrics) {
        let connection: Connection?

        if transaction.resourceFetchType == .localCache {
            connection = nil
        } else {
            connection = Connection(
                negotiatedProtocol: transaction.networkProtocolName.map(NegotiatedProtocol.init),
                isReused: transaction.isReusedConnection,
                localAddress: transaction.localAddress,
                localPort: transaction.localPort,
                remoteAddress: transaction.remoteAddress,
                remotePort: transaction.remotePort,
                isProxyConnection: transaction.isProxyConnection,
                tlsVersion: transaction.negotiatedTLSProtocolVersion.flatMap { TLSVersion(rawValue: $0.rawValue) },
                tlsCipherSuite: transaction.negotiatedTLSCipherSuite?.rawValue,
                domainLookup: Interval(
                    start: transaction.domainLookupStartDate,
                    end: transaction.domainLookupEndDate
                ),
                connect: Interval(
                    start: transaction.connectStartDate,
                    end: transaction.connectEndDate
                ),
                secureConnection: Interval(
                    start: transaction.secureConnectionStartDate,
                    end: transaction.secureConnectionEndDate
                )
            )
        }

        self.init(
            url: transaction.request.url,
            fetchStart: transaction.fetchStartDate,
            requestStart: transaction.requestStartDate,
            requestEnd: transaction.requestEndDate,
            responseStart: transaction.responseStartDate,
            responseEnd: transaction.responseEndDate,
            requestHeaderBytesSent: Int(transaction.countOfRequestHeaderBytesSent),
            requestBodyBytesSent: Int(transaction.countOfRequestBodyBytesSent),
            requestBodyBytesBeforeEncoding: Int(transaction.countOfRequestBodyBytesBeforeEncoding),
            responseHeaderBytesReceived: Int(transaction.countOfResponseHeaderBytesReceived),
            responseBodyBytesReceived: Int(transaction.countOfResponseBodyBytesReceived),
            responseBodyBytesAfterDecoding: Int(transaction.countOfResponseBodyBytesAfterDecoding),
            connection: connection
        )
    }
}

extension Internals.TransactionMetrics.NegotiatedProtocol {

    /// `URLSession` reports the ALPN name, such as `http/1.1`, `h2` or `h3`.
    package init(_ name: String) {
        switch name {
        case "http/1.1", "http/1.0":
            self = .http1_1
        case "h2":
            self = .http2
        default:
            self = .other(name)
        }
    }
}

extension Internals.TransactionMetrics.TLSVersion {

    /// The IANA value of the protocol version, as `tls_protocol_version_t` carries it.
    package init?(rawValue: UInt16) {
        switch rawValue {
        case 0x0301:
            self = .tls10
        case 0x0302:
            self = .tls11
        case 0x0303:
            self = .tls12
        case 0x0304:
            self = .tls13
        default:
            return nil
        }
    }
}

#endif
