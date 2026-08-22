//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOSSL

extension Internals {

    package struct SecureConnection: Sendable {

        // MARK: - Internal properties

        /// - Note: Mirrors exactly what AsyncHTTPClient's NIOTransportServices bridge
        /// (`TLSConfiguration.getNWProtocolTLSOptions`) can carry over into native
        /// `sec_protocol_options` when running on Network.framework. `certificateChain`,
        /// `privateKey`, `keyLogger`, and `.noHostnameVerification` trap there via
        /// `precondition` — reaching this transport with any of them set would crash the
        /// process, not just silently downgrade. The others listed below (`cipherSuiteValues`,
        /// `additionalTrustRoots`, `renegotiationSupport`, `signingSignatureAlgorithms`,
        /// `verifySignatureAlgorithms`, `sendCANameList`, `shutdownTimeout`, `pskHint`,
        /// `pskIdentityResolver`) aren't rejected there at all — they're read from the built
        /// `TLSConfiguration` and then never looked at again, so the connection would silently
        /// negotiate without them rather than fail loudly.
        package var isCompatibleWithNetworkFramework: Bool {
            #if canImport(Darwin)
            return certificateChain == nil
                && privateKey == nil
                && keyLogger == nil
                && certificateVerification != .noHostnameVerification
                && cipherSuites == nil
                && cipherSuiteValues == nil
                && additionalTrustRoots == nil
                && renegotiationSupport == nil
                && signingSignatureAlgorithms == nil
                && verifySignatureAlgorithms == nil
                && sendCANameList == nil
                && shutdownTimeout == nil
                && pskHint == nil
                && pskIdentityResolver == nil
            #else
            return false
            #endif
        }

        package var certificateChain: CertificateChain?
        package var certificateVerification: NIOSSL.CertificateVerification?
        package var useDefaultTrustRoots: Bool = false
        package var trustRoots: TrustRoots?
        package var additionalTrustRoots: [AdditionalTrustRoots]?
        package var privateKey: PrivateKeySource?
        package var signingSignatureAlgorithms: [NIOSSL.SignatureAlgorithm]?
        package var verifySignatureAlgorithms: [NIOSSL.SignatureAlgorithm]?
        package var sendCANameList: Bool?
        package var renegotiationSupport: NIOSSL.NIORenegotiationSupport?
        package var shutdownTimeout: TimeAmount?
        package var pskHint: String?
        package var applicationProtocols: [String]?
        package var keyLogger: SSLKeyLogger?
        package var pskIdentityResolver: SSLPSKIdentityResolver?
        package var minimumTLSVersion: NIOSSL.TLSVersion?
        package var maximumTLSVersion: NIOSSL.TLSVersion?
        package var cipherSuites: String?
        package var cipherSuiteValues: [NIOSSL.NIOTLSCipher]?

        // MARK: - Inits

        package init() {}

        // MARK: - Internal methods

        package func build() throws -> NIOSSL.TLSConfiguration {
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

    package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        let isSecurityPropertiesEqual =
            lhs.certificateChain == rhs.certificateChain
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

extension Internals.SecureConnection {

    package struct Output: Sendable {
        package let tlsConfiguration: TLSConfiguration
    }
}
