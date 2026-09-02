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
        /// `pskIdentityResolver`, `tlsPins`) aren't rejected there at all — they're read from the
        /// built `TLSConfiguration` and then never looked at again, so the connection would
        /// silently negotiate without them rather than fail loudly.
        package var isCompatibleWithNetworkFramework: Bool {
            #if canImport(Darwin)
            return networkFrameworkIncompatibilityReasons().isEmpty
            #else
            return false
            #endif
        }

        package var certificateChain: CertificateChain?
        package var certificateVerification: NIOSSL.CertificateVerification?
        package var useDefaultTrustRoots: Bool = false
        package var trustRoots: TrustRoots?
        package var additionalTrustRoots: [AdditionalTrustRoots]?
        package var tlsPinningPolicy: SPKIPinningPolicy?
        package var tlsPins: [SPKIHash]?
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

        /// Backs `isCompatibleWithNetworkFramework` above -- single source of truth instead of
        /// two lists that can drift apart again the way the original 4-field check did.
        package func networkFrameworkIncompatibilityReasons() -> [Internals.ExecutorIncompatibilityReason] {
            var reasons: [Internals.ExecutorIncompatibilityReason] = []

            if certificateChain != nil { reasons.append(.certificateChain) }
            if privateKey != nil { reasons.append(.privateKey) }
            if keyLogger != nil { reasons.append(.keyLogger) }
            if certificateVerification == .noHostnameVerification {
                reasons.append(.noHostnameVerificationUnderNetworkFramework)
            }
            if cipherSuites != nil { reasons.append(.cipherSuites) }
            if cipherSuiteValues != nil { reasons.append(.cipherSuiteValues) }
            if additionalTrustRoots != nil { reasons.append(.additionalTrustRootsUnderNetworkFramework) }
            if tlsPins != nil { reasons.append(.tlsPinning) }
            if renegotiationSupport != nil { reasons.append(.renegotiationSupport) }
            if signingSignatureAlgorithms != nil { reasons.append(.signingSignatureAlgorithms) }
            if verifySignatureAlgorithms != nil { reasons.append(.verifySignatureAlgorithms) }
            if sendCANameList != nil { reasons.append(.sendCANameList) }
            if shutdownTimeout != nil { reasons.append(.shutdownTimeout) }
            if pskHint != nil { reasons.append(.pskHint) }
            if pskIdentityResolver != nil { reasons.append(.pskIdentityResolver) }

            return reasons
        }

        /// Deliberately does *not* check `certificateChain`/`privateKey`/`additionalTrustRoots`/
        /// `.noHostnameVerification`/`tlsPins` -- all five are reachable under URLSession, via a
        /// Keychain round-trip (`certificateChain`/`privateKey`) or `SecTrust`/`SecPolicy`
        /// (everything else), unlike under Network.framework (see
        /// `networkFrameworkIncompatibilityReasons()` above, where SPKI pinning stays
        /// incompatible -- it's wired only through `SPKIPinningConfiguration`, which
        /// AsyncHTTPClient's NIOTransportServices bridge never consults). `Internals.ServerTrustPolicy`
        /// recomputes each pin's SPKI digest itself from the peer's leaf certificate rather than
        /// going through `SPKIPinningConfiguration` at all. Whether the app actually carries the
        /// Keychain Sharing entitlement the identity round-trip needs is a runtime fact this
        /// static check cannot see; a missing entitlement surfaces at identity-build time as its
        /// own runtime error, not as a reason in this list.
        package func urlSessionIncompatibilityReasons() -> [Internals.ExecutorIncompatibilityReason] {
            var reasons: [Internals.ExecutorIncompatibilityReason] = []

            if signingSignatureAlgorithms != nil { reasons.append(.signingSignatureAlgorithms) }
            if verifySignatureAlgorithms != nil { reasons.append(.verifySignatureAlgorithms) }
            if sendCANameList != nil { reasons.append(.sendCANameList) }
            if renegotiationSupport != nil { reasons.append(.renegotiationSupport) }
            if shutdownTimeout != nil { reasons.append(.shutdownTimeout) }
            if pskHint != nil { reasons.append(.pskHint) }
            if pskIdentityResolver != nil { reasons.append(.pskIdentityResolver) }
            if keyLogger != nil { reasons.append(.keyLogger) }
            if cipherSuites != nil { reasons.append(.cipherSuites) }
            if cipherSuiteValues != nil { reasons.append(.cipherSuiteValues) }

            return reasons
        }

        package func build() throws -> Output {
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

            return try .init(
                tlsConfiguration: tlsConfiguration,
                tlsPinning: buildTLSPinning()
            )
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

        private func buildTLSPinning() throws -> SPKIPinningConfiguration? {
            guard let tlsPins else {
                return nil
            }

            let pins = try tlsPins.reduce(into: [AsyncHTTPClient.SPKIHash]()) {
                try $1.resolve(&$0)
            }

            return .init(
                pins: pins,
                policy: tlsPinningPolicy ?? .strict
            )
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
            && lhs.tlsPins == rhs.tlsPins
            && lhs.tlsPinningPolicy == rhs.tlsPinningPolicy
    }
}

extension Internals.SecureConnection {

    package struct Output: Sendable {
        package let tlsConfiguration: TLSConfiguration
        package let tlsPinning: SPKIPinningConfiguration?
    }
}
