/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL
import AsyncHTTPClient
import NIOCore

extension Internals {

    struct SecureConnection: Sendable {

        // MARK: - Internal properties

        var isCompatibleWithNetworkFramework: Bool {
            #if canImport(Darwin)
            return certificateChain == nil
                && privateKey == nil
                && keyLogger == nil
                && cipherSuites == nil
            #else
            return false
            #endif
        }

        var certificateChain: CertificateChain?
        var certificateVerification: NIOSSL.CertificateVerification?
        var useDefaultTrustRoots: Bool = false
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
        var keyLogger: SSLKeyLogger?
        var pskIdentityResolver: SSLPSKIdentityResolver?
        var minimumTLSVersion: NIOSSL.TLSVersion?
        var maximumTLSVersion: NIOSSL.TLSVersion?
        var cipherSuites: String?
        var cipherSuiteValues: [NIOSSL.NIOTLSCipher]?

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        func build() throws -> NIOSSL.TLSConfiguration {
            var tlsConfiguration = try makeTLSConfigurationByContext()

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

            if useDefaultTrustRoots {
                tlsConfiguration.trustRoots = .default
            } else if let trustRoots {
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

            if let keyLogger {
                tlsConfiguration.keyLogCallback = {
                    keyLogger($0)
                }
            }

            if let pskIdentityResolver {
                tlsConfiguration.pskClientProvider = {
                    try pskIdentityResolver($0)
                }
            }

            return tlsConfiguration
        }

        // MARK: - Private methods

        private func makeTLSConfigurationByContext() throws -> NIOSSL.TLSConfiguration {
            var tlsConfiguration: TLSConfiguration

            tlsConfiguration = .makeClientConfiguration()

            if let certificateChain {
                tlsConfiguration.certificateChain = try certificateChain.build()
            }

            if let privateKey {
                tlsConfiguration.privateKey = try privateKey.build()
            }

            return tlsConfiguration
        }
    }
}

// MARK: - Equatable

extension Internals.SecureConnection: Equatable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        let isSecurityPropertiesEqual = lhs.certificateChain == rhs.certificateChain
        && lhs.privateKey == rhs.privateKey
        && lhs.keyLogger === rhs.keyLogger
        && lhs.cipherSuites == rhs.cipherSuites

        return isSecurityPropertiesEqual
        && lhs.certificateVerification == rhs.certificateVerification
        && lhs.trustRoots == rhs.trustRoots
        && lhs.additionalTrustRoots == rhs.additionalTrustRoots
        && lhs.signingSignatureAlgorithms == rhs.signingSignatureAlgorithms
        && lhs.verifySignatureAlgorithms == rhs.verifySignatureAlgorithms
        && lhs.sendCANameList == rhs.sendCANameList
        && lhs.renegotiationSupport == rhs.renegotiationSupport
        && lhs.shutdownTimeout == rhs.shutdownTimeout
        && lhs.pskHint == rhs.pskHint
        && lhs.applicationProtocols == rhs.applicationProtocols
        && lhs.pskIdentityResolver === rhs.pskIdentityResolver
        && lhs.minimumTLSVersion == rhs.minimumTLSVersion
        && lhs.maximumTLSVersion == rhs.maximumTLSVersion
        && lhs.cipherSuiteValues == rhs.cipherSuiteValues
    }
}
