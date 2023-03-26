/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL
import AsyncHTTPClient
import NIOCore

public typealias SignatureAlgorithm = NIOSSL.SignatureAlgorithm
public typealias NIORenegotiationSupport = NIOSSL.NIORenegotiationSupport
public typealias NIOSSLKeyLogCallback = NIOSSL.NIOSSLKeyLogCallback
public typealias NIOSSLSecureBytes = NIOSSL.NIOSSLSecureBytes
public typealias NIOPSKClientIdentityCallback = NIOSSL.NIOPSKClientIdentityCallback
public typealias NIOPSKServerIdentityCallback = NIOSSL.NIOPSKServerIdentityCallback
public typealias CertificateVerification = NIOSSL.CertificateVerification
public typealias NIOTLSCipher = NIOSSL.NIOTLSCipher
public typealias TLSVersion = NIOSSL.TLSVersion

extension Session {

    public struct SecureConnection {

        public var context: ConnectionContext
        public var certificateChain: ChainCertificate?
        public var certificateVerification: CertificateVerification?
        public var trustRoots: TrustRoots?
        public var additionalTrustRoots: AdditionalTrustRoots?
        public var privateKey: PrivateKeySource?
        public var signingSignatureAlgorithms: [SignatureAlgorithm]?
        public var verifySignatureAlgorithms: [SignatureAlgorithm]?
        public var sendCANameList: Bool?
        public var renegotiationSupport: NIORenegotiationSupport?
        public var shutdownTimeout: TimeAmount?
        public var pskHint: String?
        public var applicationProtocols: [String]?
        public var keyLogCallback: NIOSSLKeyLogCallback?
        public var pskClientCallback: NIOPSKClientIdentityCallback?
        public var pskServerCallback: NIOPSKServerIdentityCallback?
        public var minimumTLSVersion: TLSVersion?
        public var maximumTLSVersion: TLSVersion?
        public var cipherSuites: String?
        public var cipherSuiteValues: [NIOTLSCipher]?

        public init(_ context: ConnectionContext) {
            self.context = context
        }
    }
}

extension Session.SecureConnection {

    func build() throws -> NIOSSL.TLSConfiguration {
        var tlsConfiguration: TLSConfiguration

        switch context {
        case .client:
            tlsConfiguration = .makeClientConfiguration()

            if let certificateChain {
                tlsConfiguration.certificateChain = try certificateChain.build()
            }

            if let privateKey {
                tlsConfiguration.privateKey = try privateKey.build()
            }
        case .server:
            guard
                let source = try certificateChain?.build(),
                let privateKey = try privateKey?.build()
            else { fatalError() }

            tlsConfiguration = .makeServerConfiguration(
                certificateChain: source,
                privateKey: privateKey
            )
        }

        if let minimumTLSVersion {
            tlsConfiguration.minimumTLSVersion = minimumTLSVersion
        }

        if let maximumTLSVersion {
            tlsConfiguration.maximumTLSVersion = maximumTLSVersion
        }

        if let cipherSuites {
            tlsConfiguration.cipherSuites = cipherSuites
        }

        if let cipherSuiteValues {
            tlsConfiguration.cipherSuiteValues = cipherSuiteValues
        }

        if let trustRoots {
            tlsConfiguration.trustRoots = try trustRoots.build()
        }

        if let additionalTrustRoots {
            tlsConfiguration.additionalTrustRoots = try additionalTrustRoots.build()
        }

        if let certificateVerification {
            tlsConfiguration.certificateVerification = certificateVerification
        }

        if let signingSignatureAlgorithms {
            tlsConfiguration.signingSignatureAlgorithms = signingSignatureAlgorithms
        }

        if let verifySignatureAlgorithms {
            tlsConfiguration.verifySignatureAlgorithms = verifySignatureAlgorithms
        }

        if let sendCANameList {
            tlsConfiguration.sendCANameList = sendCANameList
        }

        if let renegotiationSupport {
            tlsConfiguration.renegotiationSupport = renegotiationSupport
        }

        if let shutdownTimeout {
            tlsConfiguration.shutdownTimeout = shutdownTimeout
        }

        if let pskHint {
            tlsConfiguration.pskHint = pskHint
        }

        if let applicationProtocols {
            tlsConfiguration.applicationProtocols = applicationProtocols
        }

        if let keyLogCallback {
            tlsConfiguration.keyLogCallback = keyLogCallback
        }

        return tlsConfiguration
    }
}
