//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals {

    package enum TrustRoots: Sendable, Hashable {

        case file(String)

        case bytes([UInt8])

        case certificates([Internals.Certificate])

        // MARK: - Inits

        package init() {
            self = .certificates([])
        }

        // MARK: - Internal methods

        package mutating func append(_ certificate: Internals.Certificate) {
            switch self {
            case .file(let path):
                self = .certificates([.init(path, format: .pem), certificate])
            case .bytes(let bytes):
                self = .certificates([.init(bytes, format: .pem), certificate])
            case .certificates(let certificates):
                self = .certificates(certificates + [certificate])
            }
        }

        /// Portable counterpart to `resolvedCertificates()`: the DER bytes of every certificate
        /// this configuration resolves to, without NIOSSL. What `ServerTrustPolicy.resolve(from:)`
        /// (the `.urlSession` trust-root consumer) uses instead of `resolvedCertificates()` +
        /// `.toDERBytes()`.
        ///
        /// - Important: `.bytes` matches `resolvedCertificates()`'s own single-certificate
        /// `Certificate(bytes, format: .pem).build()` call. See `Certificate.resolvedDERBytes()`'s
        /// doc comment for why `.bytes` truncates to the first certificate.
        package func resolvedDERBytes() throws -> [Data] {
            switch self {
            case .file(let file):
                return try Internals.Certificate(file, format: .pem).resolvedDERBytes()
            case .bytes(let bytes):
                return try Internals.Certificate(bytes, format: .pem).resolvedDERBytes()
            case .certificates(let certificates):
                return try certificates.flatMap { try $0.resolvedDERBytes() }
            }
        }

        #if canImport(NIOCore)
        package func build() throws -> NIOSSLTrustRoots {
            switch self {
            case .file(let file):
                return .file(file)
            case .bytes(let bytes):
                return .certificates(try NIOSSLCertificate.fromPEMBytes(bytes))
            case .certificates(let certificates):
                return .certificates(
                    try certificates.reduce(into: []) {
                        try $0.append(contentsOf: $1.build())
                    }
                )
            }
        }

        /// The flat list of `NIOSSLCertificate`s this configuration resolves to: what a trust
        /// evaluator needs to set as anchors, as opposed to `build()`'s `NIOSSLTrustRoots`, which
        /// stays a `.file` reference rather than reading it eagerly.
        package func resolvedCertificates() throws -> [NIOSSLCertificate] {
            switch self {
            case .file(let file):
                return try Internals.Certificate(file, format: .pem).build()
            case .bytes(let bytes):
                return try Internals.Certificate(bytes, format: .pem).build()
            case .certificates(let certificates):
                return try certificates.flatMap { try $0.build() }
            }
        }
        #endif
    }
}
