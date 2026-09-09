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

        /// - Note: `certificateChain`/`privateKey` (mTLS, via `tlsLocalIdentityNetworkFramework`),
        /// `tlsPins` (SPKI pinning), and `additionalTrustRoots` all reach Network.framework now,
        /// through the two trust/identity hooks `Internals.NIOTrustEvaluator`/
        /// `makeLocalIdentityForNetworkFramework()` install. `additionalTrustRoots` has no native
        /// Network.framework counterpart at all (unlike `trustRoots`, which `getNWProtocolTLSOptions`
        /// does carry over) -- `Internals.NIOTrustEvaluator` is what makes it work there, installing
        /// `tlsCustomVerificationNetworkFramework` whenever `additionalTrustRoots` is configured,
        /// independently of whether SPKI pinning is also active (`build()`'s NIOSSL-facing
        /// `tlsCustomVerification` stays gated to pins only, since NIOSSL already honors
        /// `additionalTrustRoots` natively via `TLSConfiguration` and doesn't need the assist).
        /// What's left genuinely unreachable under Network.framework: `keyLogger` (no
        /// Network.framework equivalent at all) and `.noHostnameVerification` (traps via
        /// `precondition` unless a custom verification callback is also installed -- see
        /// `getNWProtocolTLSOptions`). The rest (`cipherSuiteValues`, `renegotiationSupport`,
        /// `signingSignatureAlgorithms`, `verifySignatureAlgorithms`, `sendCANameList`,
        /// `shutdownTimeout`, `pskHint`, `pskIdentityResolver`) aren't rejected there at all —
        /// they're read from the built `TLSConfiguration` and then never looked at again, so the
        /// connection would silently negotiate without them rather than fail loudly.
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

        /// - Parameter isCompatibleWithNetworkFramework: Whether the caller is actually going to
        /// run this over Network.framework. When `false`, skips `makeLocalIdentityForNetworkFramework()`
        /// entirely rather than performing its Keychain round-trip only to hand back a handle
        /// nothing will use -- e.g. a `.nio` (plain-socket) client has no use for a Network.framework
        /// identity, and shouldn't need Keychain Sharing entitlement (or a working Keychain at
        /// all) just because `certificateChain`/`privateKey` happen to be configured for some
        /// other executor's mTLS. Defaults to `true`, matching this method's original unconditional
        /// behavior, for callers that don't know or don't care which executor will consume this.
        package func build(isCompatibleWithNetworkFramework: Bool = true) throws -> Output {
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

            // NIOSSL already honors `additionalTrustRoots` natively, via the plain
            // `tlsConfiguration.additionalTrustRoots` assignment above -- unlike
            // `tlsCustomVerificationNetworkFramework` below, its custom-verification callback
            // stays reserved for what it can't do on its own (SPKI pinning), so a
            // `trustEvaluator` built only for `additionalTrustRoots` never gets attached here.
            let hasPins = !(tlsPins ?? []).isEmpty

            #if canImport(Darwin)
            return .init(
                tlsConfiguration: tlsConfiguration,
                tlsCustomVerification: hasPins ? trustEvaluator?.tlsCustomVerification : nil,
                tlsCustomVerificationNetworkFramework: trustEvaluator?.tlsCustomVerificationNetworkFramework,
                localIdentityHandle: isCompatibleWithNetworkFramework ? try makeLocalIdentityForNetworkFramework() : nil
            )
            #else
            return .init(
                tlsConfiguration: tlsConfiguration,
                tlsCustomVerification: hasPins ? trustEvaluator?.tlsCustomVerification : nil
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
        /// Builds the `RawBytesIdentityBuilder.Handle` for mTLS under Network.framework when both
        /// `certificateChain` and `privateKey` are configured -- the same Keychain round-trip
        /// `Internals.URLSessionIdentityPolicy` already uses for `.urlSession`, via the shared
        /// `RawBytesIdentityBuilder` entry points.
        ///
        /// Returns the whole `Handle`, not just its `.identity` -- `Internals.Client` holds onto it
        /// and calls `RawBytesIdentityBuilder.remove(_:)` from its own `deinit`, mirroring
        /// `URLSessionIdentityPolicy`'s lifecycle exactly, just one layer further down the chain
        /// (`Output` -> `Internals.Session.Configuration.Output` -> `Internals.Client`).
        private func makeLocalIdentityForNetworkFramework() throws -> Internals.RawBytesIdentityBuilder.Handle? {
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
                )

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

        /// The Keychain-backed identity for mTLS under Network.framework, when both
        /// `certificateChain` and `privateKey` are configured -- carries `.identity` for
        /// `HTTPClient.Configuration.tlsLocalIdentityNetworkFramework` *and* the Keychain-item
        /// label needed to remove it again, since whoever ends up owning this identity's lifetime
        /// (`Internals.Client`, currently) needs both.
        package let localIdentityHandle: Internals.RawBytesIdentityBuilder.Handle?
        #endif
    }
}
