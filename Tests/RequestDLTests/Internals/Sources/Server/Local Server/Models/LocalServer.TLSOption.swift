/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOSSL
import NIOHTTP1
@testable import RequestDL

extension LocalServer {

    enum TLSOption: Sendable, Hashable {
        case none
        case client(CertificateResource)
        case psk(Data, String)

        static func makeDefaultConfiguration() throws -> NIOSSL.TLSConfiguration {
            let server = Certificates().server()

            return .makeServerConfiguration(
                certificateChain: try NIOSSLCertificate.fromPEMFile(
                    server.certificateURL.absolutePath(percentEncoded: false)
                ).map { .certificate($0) },
                privateKey: .file(server.privateKeyURL.absolutePath(percentEncoded: false))
            )
        }

        func build() throws -> NIOSSL.TLSConfiguration {
            switch self {
            case .none:
                return try Self.makeDefaultConfiguration()
            case .psk(let key, let identity):
                var tlsConfiguration: TLSConfiguration = .makePreSharedKeyConfiguration()
                tlsConfiguration.minimumTLSVersion = .tlsv1
                tlsConfiguration.maximumTLSVersion = .tlsv12

                tlsConfiguration.pskServerCallback = { hint, clientIdentity in
                    var bytes = NIOSSLSecureBytes()
                    bytes.append(key)
                    bytes.append(":\(identity)".utf8)
                    bytes.append(":\(clientIdentity)".utf8)
                    bytes.append(":\(hint)".utf8)
                    return .init(key: bytes)
                }
                tlsConfiguration.pskHint = "pskHint"

                return tlsConfiguration
            case .client(let client):
                var tlsConfiguration = try Self.makeDefaultConfiguration()
                tlsConfiguration.trustRoots = .file(client.certificateURL.absolutePath(percentEncoded: false))
                tlsConfiguration.certificateVerification = .noHostnameVerification
                return tlsConfiguration
            }
        }
    }
}
