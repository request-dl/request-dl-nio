//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOSSL

#if canImport(Darwin)
import Security
#endif

extension Internals {

    package struct SecureConnection: Sendable {

        // MARK: - Internal properties

        /// - Note: `certificateChain`/`privateKey` (mTLS, via `tlsLocalIdentityNetworkFramework`)
        /// and `tlsPins` (SPKI pinning, via `tlsCustomVerificationNetworkFramework`) both reach
        /// Network.framework now, through the two trust/identity hooks
        /// `Internals.NIOTrustEvaluator`/`makeLocalIdentityForNetworkFramework()` install. What's
        /// left genuinely unreachable there: `keyLogger` (no Network.framework equivalent at all)
        /// and `.noHostnameVerification` (traps via `precondition` unless a custom verification
        /// callback is also installed -- see `getNWProtocolTLSOptions`). `additionalTrustRoots`
        /// only reaches Network.framework's *native* trust-root handling when SPKI pinning isn't
        /// also configured; when it is, `Internals.NIOTrustEvaluator` reads it directly instead.
        /// The rest (`cipherSuiteValues`, `renegotiationSupport`, `signingSignatureAlgorithms`,
        /// `verifySignatureAlgorithms`, `sendCANameList`, `shutdownTimeout`, `pskHint`,
        /// `pskIdentityResolver`) aren't rejected there at all — they're read from the built
        /// `TLSConfiguration` and then never looked at again, so the connection would silently
        /// negotiate without them rather than fail loudly.
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
        package var tlsPinningPolicy: Internals.SPKIPinningPolicy?
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

            if keyLogger != nil { reasons.append(.keyLogger) }
            if certificateVerification == .noHostnameVerification {
                reasons.append(.noHostnameVerificationUnderNetworkFramework)
            }
            if cipherSuites != nil { reasons.append(.cipherSuites) }
            if cipherSuiteValues != nil { reasons.append(.cipherSuiteValues) }
            if additionalTrustRoots != nil, tlsPins == nil {
                reasons.append(.additionalTrustRootsUnderNetworkFramework)
            }
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
        /// (everything else). They're also all reachable under Network.framework now (see
        /// `networkFrameworkIncompatibilityReasons()` above) via `Internals.NIOTrustEvaluator`/
        /// `makeLocalIdentityForNetworkFramework()`, so this list and that one agree on every field
        /// except `.noHostnameVerification` and `keyLogger`, which stay Network.framework-specific
        /// gaps. Whether the app actually carries the Keychain Sharing entitlement the identity
        /// round-trip needs is a runtime fact this static check cannot see; a missing entitlement
        /// surfaces at identity-build time as its own runtime error, not as a reason in this list.
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

            let trustEvaluator = try Internals.NIOTrustEvaluator.resolve(from: self)

            #if canImport(Darwin)
            return try .init(
                tlsConfiguration: tlsConfiguration,
                tlsCustomVerification: trustEvaluator?.tlsCustomVerification,
                tlsCustomVerificationNetworkFramework: trustEvaluator?.tlsCustomVerificationNetworkFramework,
                tlsLocalIdentityNetworkFramework: try makeLocalIdentityForNetworkFramework()
            )
            #else
            return .init(
                tlsConfiguration: tlsConfiguration,
                tlsCustomVerification: trustEvaluator?.tlsCustomVerification
            )
            #endif
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

        #if canImport(Darwin)
        /// Builds the `SecIdentity` for `HTTPClient.Configuration.tlsLocalIdentityNetworkFramework`
        /// (mTLS under Network.framework) when both `certificateChain` and `privateKey` are
        /// configured -- the same Keychain round-trip `Internals.URLSessionIdentityPolicy` already
        /// uses for `.urlSession`, via the shared `RawBytesIdentityBuilder` entry points.
        ///
        /// - Note: Unlike `URLSessionIdentityPolicy`, this doesn't hold on to the returned
        /// `RawBytesIdentityBuilder.Handle` to remove it again later -- there's no natural place in
        /// `.nio`'s client lifecycle to call `RawBytesIdentityBuilder.remove(_:)` from (see
        /// `Internals.Client`'s `deinit`, which only shuts down the underlying `HTTPClient`).
        /// `makeIdentity`'s Keychain items are labeled deterministically from the certificate's own
        /// bytes and tolerate being re-added, so this leaves at most one item behind per distinct
        /// client identity a process configures, rather than growing unbounded.
        private func makeLocalIdentityForNetworkFramework() throws -> SecIdentity? {
            switch (certificateChain, privateKey) {
            case (nil, nil):
                return nil

            case (.some(let certificateChain), .some(let privateKey)):
                let derCertificates = try RawBytesIdentityBuilder.certificateDERs(from: certificateChain)

                guard let leaf = derCertificates.first else {
                    throw Internals.URLSessionIdentityPolicy.ConfigurationError.emptyCertificateChain
                }

                let privateKeyDER = try RawBytesIdentityBuilder.privateKeyDER(from: privateKey)

                return try RawBytesIdentityBuilder.makeIdentity(
                    certificateDER: leaf,
                    privateKeyDER: privateKeyDER
                ).identity

            case (.some, nil), (nil, .some):
                throw Internals.URLSessionIdentityPolicy.ConfigurationError.incompleteClientIdentity
            }
        }
        #endif
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

        /// Installs on `HTTPClient.Configuration.tlsCustomVerification` when SPKI pinning is
        /// configured -- `nil` otherwise, leaving the NIOSSL backend's own native trust-root
        /// handling completely untouched.
        package let tlsCustomVerification:
            (@Sendable ([NIOSSLCertificate], EventLoopPromise<NIOSSLVerificationResult>) -> Void)?

        #if canImport(Darwin)
        /// Installs on `HTTPClient.Configuration.tlsCustomVerificationNetworkFramework` when SPKI
        /// pinning is configured.
        package let tlsCustomVerificationNetworkFramework:
            (@Sendable (SecTrust, @escaping @Sendable (Bool) -> Void) -> Void)?

        /// Installs on `HTTPClient.Configuration.tlsLocalIdentityNetworkFramework` when both
        /// `certificateChain` and `privateKey` are configured (mTLS).
        package let tlsLocalIdentityNetworkFramework: SecIdentity?
        #endif
    }
}
