//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIO
import NIOHTTP1
import NIOSSL
#endif

import RequestDLInternals

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension LocalServer {

    enum TLSOption: Sendable, Hashable {
        case none
        case client(CertificateResource)
        case psk(Data, String)

        #if canImport(NIOCore)
        static func makeDefaultConfiguration() throws -> NIOSSL.TLSConfiguration {
            let server = Certificates().server()

            return try .makeServerConfiguration(
                certificateChain: NIOSSLCertificate.fromPEMFile(
                    server.certificateURL.absolutePath(percentEncoded: false)
                ).map { .certificate($0) },
                privateKey: .privateKey(
                    .init(
                        file: server.privateKeyURL.absolutePath(percentEncoded: false),
                        format: server.format.build()
                    )
                )
            )
        }

        func build() throws -> NIOSSL.TLSConfiguration {
            switch self {
            case .none:
                return try Self.makeDefaultConfiguration()
            case .psk(let key, let identity):
                var tlsConfiguration: TLSConfiguration = .makePreSharedKeyConfiguration()
                tlsConfiguration.minimumTLSVersion = .tlsv1
                tlsConfiguration.maximumTLSVersion = .tlsv13

                tlsConfiguration.pskServerProvider = { context in
                    var bytes = NIOSSLSecureBytes()
                    bytes.append(key)
                    bytes.append(":\(identity)".utf8)
                    bytes.append(":\(context.clientIdentity)".utf8)
                    if let hint = context.hint {
                        bytes.append(":\(hint)".utf8)
                    }
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
        #endif

        #if canImport(Darwin)
        /// The `SecIdentity` ``PortableServer`` presents for every ``TLSOption`` case: there is
        /// no public Network.framework API for a PSK provider the way NIOSSL's
        /// `pskServerProvider` is, and none for requiring/verifying a client certificate against
        /// an arbitrary trust root either, so `.psk`/`.client` can't be told apart from `.none`
        /// down here. A ``TLSOption`` that actually needs either of those stays
        /// `#if canImport(NIOCore)`-gated at the call site instead of pretending to work here.
        func serverIdentity() throws -> Internals.IdentityHandle {
            let server = Certificates().server()

            let certificateDER = try Internals.CertificateChain.file(
                server.certificateURL.absolutePath(percentEncoded: false)
            ).resolvedDERBytes()[0]

            let privateKeyDER = try Internals.RawBytesIdentityBuilder.privateKeyDER(
                from: .privateKey(
                    .init(
                        server.privateKeyURL.absolutePath(percentEncoded: false),
                        format: server.format
                    )
                )
            )

            return try Internals.RawBytesIdentityBuilder.makeIdentity(
                certificateDER: certificateDER,
                privateKeyDER: privateKeyDER
            )
        }
        #endif
    }
}
