//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOHTTP1
import NIOSSL

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif
#else
import Foundation
import RequestDLInternals
#endif

extension LocalServer {

    enum TLSOption: Sendable, Hashable {
        case none
        case client(CertificateResource)
        case psk(Data, String)
    }
}

#if canImport(NIOCore)
extension LocalServer.TLSOption {

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
}
#else
extension LocalServer.TLSOption {

    struct UnsupportedError: Swift.Error, CustomStringConvertible {
        let option: String
        var description: String {
            "LocalServer.TLSOption.\(option) has no Network.framework equivalent under a NIOCore-free build."
        }
    }

    /// Builds the `SecIdentity` `PortableServer` presents during its TLS handshake. Only `.none`
    /// (the standard test server certificate, no client verification) is reachable: `.psk` has no
    /// public `NWProtocolTLS` hook the way `NIOSSL.pskServerProvider` does, and `.client`
    /// (server-side client-certificate verification) isn't implemented on the `NWListener` side.
    /// Both throw rather than silently downgrading to `.none`, so a test that actually needs
    /// either fails loudly instead of quietly exercising the wrong TLS shape.
    func makeLocalIdentity() throws -> Internals.IdentityHandle {
        switch self {
        case .none:
            return try Self.identity(for: Certificates().server())
        case .client:
            throw UnsupportedError(option: "client(_:) (server-side mTLS verification)")
        case .psk:
            throw UnsupportedError(option: "psk(_:_:)")
        }
    }

    private static func identity(for resource: CertificateResource) throws -> Internals.IdentityHandle {
        let certificateDER = try Internals.Certificate.resolvedPEMCertificateDERBytes(
            of: Data(contentsOf: resource.certificateURL)
        )[0]

        let privateKeySource = Internals.PrivateKeySource.privateKey(
            .init(resource.privateKeyURL.absolutePath(percentEncoded: false), format: resource.format)
        )
        let privateKeyDER = try Internals.RawBytesIdentityBuilder.privateKeyDER(from: privateKeySource)

        return try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: certificateDER,
            privateKeyDER: privateKeyDER
        )
    }
}
#endif
