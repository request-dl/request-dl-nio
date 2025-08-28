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

        #if !canImport(Network)
        var certificateChain: CertificateChain?
        #endif
        var certificateVerification: NIOSSL.CertificateVerification?
        var trustRoots: TrustRoots?
        var additionalTrustRoots: [AdditionalTrustRoots]?
        #if !canImport(Network)
        var privateKey: PrivateKeySource?
        #endif
        var signingSignatureAlgorithms: [NIOSSL.SignatureAlgorithm]?
        var verifySignatureAlgorithms: [NIOSSL.SignatureAlgorithm]?
        var sendCANameList: Bool?
        var renegotiationSupport: NIOSSL.NIORenegotiationSupport?
        var shutdownTimeout: TimeAmount?
        var pskHint: String?
        var applicationProtocols: [String]?
        #if !canImport(Network)
        var keyLogger: SSLKeyLogger?
        #endif
        var pskIdentityResolver: SSLPSKIdentityResolver?
        var minimumTLSVersion: NIOSSL.TLSVersion?
        var maximumTLSVersion: NIOSSL.TLSVersion?
        #if !canImport(Network)
        var cipherSuites: String?
        #endif
        var cipherSuiteValues: [NIOSSL.NIOTLSCipher]?

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        // swiftlint:disable cyclomatic_complexity function_body_length
        func build() throws -> NIOSSL.TLSConfiguration {
            var tlsConfiguration = try makeTLSConfigurationByContext()

            if let minimumTLSVersion {
                tlsConfiguration.minimumTLSVersion = minimumTLSVersion
            }

            if let maximumTLSVersion {
                tlsConfiguration.maximumTLSVersion = maximumTLSVersion
            }

            #if !canImport(Network)
            if let cipherSuites {
                tlsConfiguration.cipherSuites = cipherSuites
            }
            #endif

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

            #if !canImport(Network)
            if let keyLogger {
                tlsConfiguration.keyLogCallback = {
                    keyLogger($0)
                }
            }
            #endif

            if let pskIdentityResolver {
                tlsConfiguration.pskClientCallback = {
                    try pskIdentityResolver($0)
                }
            }

            return tlsConfiguration
        }
        // swiftlint:enable cyclomatic_complexity function_body_length

        // MARK: - Private methods

        private func makeTLSConfigurationByContext() throws -> NIOSSL.TLSConfiguration {
            var tlsConfiguration: TLSConfiguration

            tlsConfiguration = .makeClientConfiguration()

            #if !canImport(Network)
            if let certificateChain {
                tlsConfiguration.certificateChain = try certificateChain.build()
            }
            #endif

            #if !canImport(Network)
            if let privateKey {
                tlsConfiguration.privateKey = try privateKey.build()
            }
            #endif

            return tlsConfiguration
        }
    }
}

// MARK: - Equatable

extension Internals.SecureConnection: Equatable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        #if canImport(Network)
        let isSecurityPropertiesEqual = true
        #else
        let isSecurityPropertiesEqual = lhs.certificateChain == rhs.certificateChain
        && lhs.privateKey == rhs.privateKey
        && lhs.keyLogger === rhs.keyLogger
        && lhs.cipherSuites == rhs.cipherSuites
        #endif

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
