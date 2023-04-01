/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL
import AsyncHTTPClient
import NIOCore

extension Internals {

    struct SecureConnection {

        var context: Internals.Session.Context
        var certificateChain: CertificateChain?
        var certificateVerification: NIOSSL.CertificateVerification?
        var trustRoots: TrustRoots?
        var additionalTrustRoots: [AdditionalTrustRoots]?
        var privateKey: PrivateKeySource?
        var signingSignatureAlgorithms: [NIOSSL.SignatureAlgorithm]?
        var verifySignatureAlgorithms: [NIOSSL.SignatureAlgorithm]?
        var sendCANameList: Bool?
        var renegotiationSupport: NIOSSL.NIORenegotiationSupport?
        var shutdownTimeout: TimeAmount?
        var pskHint: String?
        var applicationProtocols: [String]?
        var keyLogCallback: NIOSSL.NIOSSLKeyLogCallback?
        var pskClientCallback: NIOSSL.NIOPSKClientIdentityCallback?
        var pskServerCallback: NIOSSL.NIOPSKServerIdentityCallback?
        var minimumTLSVersion: NIOSSL.TLSVersion?
        var maximumTLSVersion: NIOSSL.TLSVersion?
        var cipherSuites: String?
        var cipherSuiteValues: [NIOSSL.NIOTLSCipher]?

        init(_ context: Internals.Session.Context) {
            self.context = context
        }
    }
}

extension Internals.SecureConnection {

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
            else {
                Internals.Log.failure(
                    """
                    The required resources for building the certificate chain \
                    or private key could not be found or accessed.
                    """
                )
            }

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
            tlsConfiguration.additionalTrustRoots = try additionalTrustRoots.map {
                try $0.build()
            }
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
