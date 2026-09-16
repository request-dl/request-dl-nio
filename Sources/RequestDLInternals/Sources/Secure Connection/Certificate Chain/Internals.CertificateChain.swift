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
import struct Foundation.URL
#endif

extension Internals {

    package enum CertificateChain: Sendable, Hashable {

        case certificates([Internals.Certificate])

        case bytes([UInt8])

        case file(String)

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

        /// Portable counterpart to `build()`, built on `Internals.Certificate`'s own DER
        /// extraction — see that type's `resolvedDERBytes()`/`resolvedPEMCertificateDERBytes(of:)`
        /// doc comments. `.bytes` and `.file` both read every certificate in the bundle here,
        /// matching `build()`'s own `NIOSSLCertificate.fromPEMBytes`/`.fromPEMFile` calls — unlike
        /// the single-certificate `Certificate.resolvedDERBytes()`, this type's `build()` never
        /// had that asymmetry to begin with.
        package func resolvedDERBytes() throws -> [Data] {
            switch self {
            case .certificates(let certificates):
                return try certificates.flatMap { try $0.resolvedDERBytes() }
            case .bytes(let bytes):
                return try Internals.Certificate.resolvedPEMCertificateDERBytes(of: Data(bytes))
            case .file(let file):
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: file))
                    return try Internals.Certificate.resolvedPEMCertificateDERBytes(of: data)
                } catch {
                    throw SecureFileLoadError(resource: .certificate, path: file, underlying: error)
                }
            }
        }

        #if canImport(NIOCore)
        package func build() throws -> [NIOSSLCertificateSource] {
            switch self {
            case .certificates(let certificates):
                return try certificates.reduce(into: []) {
                    try $0.append(
                        contentsOf: $1.build().map {
                            .certificate($0)
                        }
                    )
                }
            case .bytes(let bytes):
                return try NIOSSLCertificate.fromPEMBytes(bytes).map {
                    .certificate($0)
                }
            case .file(let file):
                return try NIOSSLCertificate.fromPEMFile(file).map {
                    .certificate($0)
                }
            }
        }
        #endif
    }
}
